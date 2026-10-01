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
- **▶ EUCLID COMET BAR — a drag HUD (steps/hits/offset, arrow-bordered, floats above the grid) + pinch-to-resize
  steps (2026-10-01, on `main`; iOS builds; DEVICE eye/feel owed — gesture interplay is genuinely untestable off-
  device). Paul: "On drag, I want something to appear above listing the steps, hits and offset, clear enough that
  it's not obscured by the user's finger (maybe sitting above the grid). It will have small up/down/left/right
  arrows bordering it to make it clear that gestures work. Change the pinch gesture to add remove steps."
  **THE HUD:** new `@State private var euclidActiveDragRow: Int?` on `ProcessorBox` — the SAME idea as the
  existing `laneReadout` (idea 18, "the value floating while a lane bar is dragged"), just scoped to WHICH row's
  gesture is live (nil = none; 0…3 = that row; -1 = the 2-finger "every row" edit) rather than carrying a value
  itself — `euclidDragHUD(_:)` reads the CURRENT steps/hits/rotate straight off the same `rows` array `euclidRow`
  is already drawing from, so it can't show a stale number lagging the gesture. **POSITIONED ABOVE THE WHOLE
  4-ROW STACK**, not per-row (`.overlay(alignment: .top) { euclidDragHUD(rows).offset(y: -58) }` on the row
  VStack) — deliberately NOT anchored to whichever row is touched, so it sits in ONE consistent, finger-clear spot
  regardless of which of the 4 rows is being dragged, matching Paul's own "maybe sitting above the grid" steer.
  Four small arrow glyphs (▲▼◀▶) border the card on all 4 sides via `.overlay(alignment:)`, doubling as a visual
  reminder of what the gestures do (not just decoration). **PINCH → STEPS:** a `UIPinchGestureRecognizer` added
  to the SAME `EuclidGesturePad` view alongside the existing pan recognizer — spread = add steps, pinch-in =
  remove, routed through the EXACT same `onStepsDelta` the +/- tap glyphs already use (kept, not replaced — pinch
  is an additional way in, not a swap). Scale is converted to discrete integer steps LOGARITHMICALLY
  (`log(scale)/log(1.15)`, ~15%/step) rather than linearly, so pinching in and spreading out feel symmetric — a
  linear mapping would weight the two directions unevenly. **A REAL CRASH CAUGHT BEFORE SHIPPING, not after:**
  `UIPinchGestureRecognizer.scale` can approach 0 if both touches land on nearly the same point; `log(0) =
  -infinity`, and converting a non-finite Double to `Int` TRAPS in Swift — caught by reasoning through the edge
  case before testing, not by a crash log; fixed with `log(max(0.05, g.scale))`. **GESTURE COEXISTENCE:** pan
  (1-2 finger drag) and pinch now share one view — both recognizers get a delegate returning `true` from
  `shouldRecognizeSimultaneously`, lifting UIKit's own default "one gesture at a time per view" restriction. Not
  expected to conflict in practice (a genuine pinch has near-zero net translation; a 2-finger pan has near-zero
  scale change — the two gestures measure nearly orthogonal things) but this is reasoning, not a device-confirmed
  fact. UI-only (GridUI.swift), no test-target reach. **DEVICE-OWED, and this is the area most resistant to
  verification by reading code — real multi-touch arbitration only shows itself on a touchscreen:** whether pan
  and pinch genuinely coexist without one swallowing the other's touches; the HUD's exact vertical offset (-58pt)
  against the REAL surrounding panel chrome — it may overlap something above the EUCLID editor that isn't visible
  from the code alone, or get clipped if an enclosing container clips its own bounds; the pinch sensitivity
  (~15%/step) and pan sensitivity (~18pt/step) feel; confirm the HUD reads clearly as "LANE N" vs "ALL LANES" for
  the two drag modes.**
- **▶ EUCLID NOTE SELECT — trimmed to 1·2·3·4·TOP, one row instead of two (2026-10-01, on `main`; iOS builds;
  DEVICE eye owed). Paul: "Change the note control to only display 1, 2, 3, 4 and top." Was all 15
  `EuclidNoteSel` cases (ALL·N1…N8·LOW·HIGH·BOT2·TOP2·CYCLE·RANDOM) spread over two chip rows; now a single row of
  5 — `N1…N4` (labelled bare "1"…"4", not "N1"…"N4" — Paul's own wording) and `HIGH` (relabelled "TOP" for this
  control specifically — same case, same engine behaviour, just Paul's preferred word for it). The full enum is
  UNTOUCHED underneath (`euclidNoteSelShown` is a new, separate display-order list; nothing was removed from
  `EuclidNoteSel` itself) — an old doc already using ALL/N5…N8/LOW/BOT2/TOP2/CYCLE/RANDOM still resolves and plays
  exactly as before, it just won't highlight any of these 5 chips (an honest "none of these," not a wrong guess).
  **A GAP CAUGHT BEFORE SHIPPING, not after:** the EUCLID storefront card (same day) defaults a fresh row 0 to
  `euclidPick = .low` — `.low` isn't one of the 5 shown, so a brand-new EUCLID would have opened with NOTHING
  highlighted, reading as broken. Fixed in the chip row's own "is this selected" check (not by changing the
  default): `.low` and `.n1` resolve to the IDENTICAL pool rank (both strike index 0 — confirmed by re-reading
  `arpPick`'s fold, not assumed), so the row now treats `cur == .low` as matching the "1" chip — a freshly-created
  EUCLID now correctly shows "1" highlighted, with zero change to what's actually heard. The now-unused
  `noteSelCases` local (`euclidRow`) and the dead 9/6-slice comment were removed. The now-orphaned DIE control
  (only shown for CYCLE/RANDOM, neither reachable via these 5 chips anymore) is left as-is — still correctly shows
  for an OLD doc that has CYCLE/RANDOM set, just not reachable from a fresh pick. UI-only (GridUI.swift), no
  test-target reach. **DEVICE-OWED:** the single-row layout at real panel width with 5 chips instead of 2 rows of
  9+6 (likely reads calmer, worth confirming); the "1" chip correctly lighting for a freshly-created row.**
- **▶ EUCLID COMET BAR — gesture controls: 1-finger drag (this row) / 2-finger drag (all rows) / tap STEPS ±
  (2026-10-01, on `main`; iOS builds; DEVICE eye/feel owed — genuinely untestable off-device). Paul: "Left/right
  drag will move the offset. Up/down will increase or decrease the hits. A thin plus sign is on the left and minus
  sign is on the right to increase/decrease steps. Two finger drag up changes all lanes' hits. Two finger drag
  left/right changes offset on all lanes." The bar goes from purely decorative (`allowsHitTesting(false)`) to
  genuinely interactive — a deliberate reversal of the earlier "must not look selectable" brief; Paul's own
  explicit ask this time, not a contradiction to flag. **THE CORE PROBLEM:** SwiftUI's native `DragGesture` reports
  POSITION but never TOUCH COUNT — there's no built-in way to tell a 1-finger drag from a 2-finger drag on the same
  gesture. Solved with a real `UIPanGestureRecognizer` (`minimumNumberOfTouches: 1, maximumNumberOfTouches: 2`)
  bridged in via a new `EuclidGesturePad: UIViewRepresentable` — `numberOfTouches` is read ONCE, at `.began`, and
  LATCHED for the rest of that gesture, so a finger lifting or landing mid-drag can't flip which mode (per-row vs
  all-rows) the drag is in partway through. `GridUI.swift` already imports UIKit (pre-existing, unrelated to this
  change) — no new import/seam concern. **LAYOUT:** the comet bar is now a `ZStack` — the existing (unchanged)
  `Canvas` drawing underneath, the new gesture pad INSET 14pt each side, and the thin `+`/`−` STEPS glyphs as a
  THIRD sibling drawn on top in that reserved margin — SwiftUI hit-tests top-down, so the small glyphs claim their
  own bounds before the pad underneath ever sees those touches; no explicit exclusion-zone logic needed. **THE
  MAPPING**, all delta-based (relative nudges, not absolute-set, so a fast repeated drag/tap keeps compounding
  naturally): 1-finger horizontal → `Δrotate` (wraps mod 16, matching the existing ROTATE dial's own range) on THIS
  row only (`euclidLineEdit4`); 1-finger vertical → `Δhits` (clamped `0…max(2,steps)`, mirroring the existing HITS
  numPair's own clamp) on this row; the `+`/`−` glyphs → `Δsteps` (clamped 2…16, pulling hits down if steps shrinks
  below it — the exact same rule the existing STEPS numPair callback already applies); 2-finger horizontal/vertical
  → the SAME two deltas via a new `euclidAllRowsEdit` (applies the shared delta to EVERY row, each still clamping
  against its OWN steps/pulses independently, so a shared nudge can't push one row somewhere a DIFFERENT row's
  range wouldn't allow). Sensitivity: ~18pt/step on both axes — a first-pass, tunable constant, deliberately
  coarser than `NumPair`'s own 14pt scrub since this bar is small and a resting finger covers a good fraction of
  it. UI-only (GridUI.swift), no test-target reach. **DEVICE-OWED, and this is the one area I genuinely cannot
  verify by reading code — gesture-recognizer behavior only shows itself on a real touchscreen:** whether
  `numberOfTouches` reads reliably at `.began` in practice (a fast 2-finger touch-down isn't always perfectly
  simultaneous at the OS level); whether the UIKit pan gesture conflicts with any ENCLOSING SwiftUI ScrollView's
  own pan-to-scroll (if the processor panel scrolls, a vertical drag starting on this bar might fight the page
  instead of adjusting hits — untested, a real risk this specific bridge pattern is known to hit); whether the
  14pt margin is actually wide enough to reliably hit the `+`/`−` glyphs without also triggering the pad underneath;
  the 18pt/step feel in the hand.**
- **▶ EUCLID COMET BAR — the rest marker made legible, a perceived-not-literal position bug (2026-10-01, on `main`;
  iOS builds; DEVICE eye owed, audio unchecked — Paul: "I can't currently check audio"). Paul, on-device: "the
  position of the notes move, not just switch on and off" when toggling HITS/REST. Re-traced the draw math
  end-to-end (not re-asserted blind a second time) — `x = xFor(i+0.5)` is computed from the loop index `i` and `n`
  alone; `invert` only ever changes whether a given `i` counts as `hit`, never `x`. So every step's HORIZONTAL
  POSITION is provably fixed regardless of invert. **THE ACTUAL CAUSE, best diagnosis without being able to see
  the device:** the rest marker was a tiny (5pt), 16%-opacity HOLLOW ring sitting next to a hit dot that's much
  bigger and, after the same-day "more dramatic" pass, glows/flashes/rings brightly — that size+opacity gulf means
  the "off" state barely registered as present at all. Toggling invert then LOOKS like a note vanishing from one
  spot and a different one appearing elsewhere (relocation), when it's actually the same fixed 8 (or N) slots
  re-lighting a different subset. **FIX:** the rest marker is now a plainly visible FILLED dot at the SAME base
  radius a resting (non-flaring) hit dot settles to (7pt, up from 5pt) at 22% white opacity (up from 16%, and
  filled rather than a thin stroked outline) — same shape family as a hit, just dim, so the fixed slot grid reads
  clearly as persistent structure regardless of which subset is lit. **HONESTLY FLAGGED:** this is a perception fix
  for the most plausible cause found by re-deriving the math, not a confirmed root-cause match against what's
  actually on screen — if the dots still read as relocating after this, the bug is somewhere I haven't found by
  code-reading alone and needs a fresh look (a device screenshot/recording would resolve this far faster than
  another round of static analysis). Audio correctness is explicitly UNVERIFIED this pass (Paul can't currently
  check it) — this fix only addresses the VISUAL legibility, not any claim about what's actually heard.
  **DEVICE-OWED:** confirm the rest/hit distinction now reads as "the same slot, different brightness" rather than
  "different notes," and separately (once audio can be checked) that INVERT audibly plays the complementary N−K
  steps, not something else.**
- **▶ EUCLID EDITOR — a more dramatic hit flash, HITS FROM moved to the bottom, half-height number steppers
  (2026-10-01, on `main`; iOS builds; DEVICE eye owed). Three quick device-driven polish asks on the same-day comet
  bar. **(1) "The hits should be brighter, with effects, and more dramatic when it hits":** the flare was one glow
  layer decaying over the SAME 1.5-step window as the lingering afterglow — bright enough to read, but no sense of
  IMPACT at the instant of the strike. Added a second, much SHORTER `burst` window (0.35 steps, independent of the
  existing `recede` afterglow) layered on top: the dot visibly SWELLS (3.5→8pt radius) at the strike, a hot WHITE
  flash core blooms at its center (fades within the same short window), and a thin ring expands outward from the
  dot — three effects stacked, all fast-decaying, so the strike reads as a distinct "hit" moment rather than just a
  brighter glow. The lingering `recede`-based glow (Stage 2) is untouched underneath — still there for the trailing
  afterglow, just no longer the ONLY thing marking a hit. **(2) "Move fixed/pool to the bottom":** the `HITS FROM`
  FIXED|POOL seg (GridUI.swift, `case .euclid:`) moved from above the 4 rows to below them, just before the shared
  GRID/SPAN footer — a machine-wide toggle reads better sitting with the row stack it affects than ahead of it.
  **(3) "Halve the height of the number selectors":** `NumPair` (the ◀▶ nudge-pair used for HITS/OF/ROTATE/DIE)
  gained an opt-in `compact: Bool = false` — halves its height (42pt→21pt, arrows+value box) and trims its font
  (17/16pt→12pt) so the smaller pill stays legible; every OTHER caller across the whole file is untouched (default
  false), since `NumPair` is shared by dozens of unrelated processor editors and a global resize would have been a
  far bigger change than asked. All 4 `numPair` calls inside `euclidRow` now pass `compact: true`; nothing else
  does. UI-only (GridUI.swift), no test-target reach. **DEVICE-OWED:** the new burst effect's timing/scale at real
  panel size (0.35-step decay, the white-core peak, the ring's reach — all first-pass, tunable); the half-height
  steppers' legibility and touch-target size now that the tap/drag-scrub hit area is half as tall.**
- **▶ EUCLID DEFAULT — a fresh card opens on a steady 4-of-4 low-note pulse, not 5-of-8/ALL (2026-09-30, on `main`;
  iOS builds; DEVICE eye/ear owed). Paul: "default the euclid page to play a 4 by 4 on a single low note, on the
  first lane, and no notes on the additional rows." The storefront "EUCLID" card (`BuildPage.swift`'s `C(...)`
  list) previously applied NO preset at all (`C("EUCLID", …, .euclid)`, no trailing closure) — a brand-new card
  opened on the struct's bare defaults (5 pulses of 8 steps, PICK=ALL), no real starting point. Now applies
  `{ $0.euclidPulses = 4; $0.euclidSteps = 4; $0.euclidPick = .low }`, matching the same `apply:` convention every
  sibling card already uses for a sensible default (e.g. TUTTI COIN/AVOID CLASHES). **Rows 1-3 silent for free** —
  nothing here touches `euclidLines`, so the existing `euclidLinesForEditing()` pad (Stage 1 of the 2026-09-30
  redesign) still derives row 0 from these 3 flat fields and pads rows 1-3 with `pulses: 0`, exactly the idle-row
  behaviour already shipped — no new code needed for "no notes on the additional rows." UI-only (BuildPage.swift),
  no test-target reach. **DEVICE-OWED:** a freshly dragged-in EUCLID actually strikes only the lowest held note,
  on every one of 4 steps, with rows 2-4 visibly empty/silent in the new 4-row editor.**
- **▶ ARP EDITOR — revised same day: sliders stacked, VELOCITY now absolute 1…100 (2026-09-30, on `main`, `288ce7e`;
  macOS 1160 green incl. 3 rewritten, iOS builds; DEVICE eye/ear owed). Direct follow-up to the layout landed earlier
  the same day. Paul: (1) stack LENGTH/VELOCITY/VELOCITY TILT on top of each other, instead of side-by-side; (2)
  VELOCITY should IGNORE the input note's own velocity and use only what the control specifies; (3) the slider
  should run 1…100, not the old 0…2 relative scale. **LAYOUT:** the three now share ONE HStack slot (was three)
  as a `VStack(spacing: 8)`, top-to-bottom in the order Paul named them — matching the OCTAVE/OCT DIR stack's own
  spacing for visual consistency within the same row. **RENAMED `arpVelScale`→`arpVelocity` throughout** (MachineParams,
  SnapParams, `AutoParamField` + its 4 exhaustive functions, `SnapshotBuilder`'s resolve, the `effective*` helper,
  `arpPick`'s own parameter across all 3 overloads, GridUI's 5 LFO-editor switches) — not just a range change but a
  vocabulary fix, since "scale" no longer described what the field does. **ENGINE:** `arpPick` no longer reads
  `pool.velocity(note)` at all — `velocity` (the resolved 1…100 control value) IS the note's entire base, with
  VELOCITY TILT still shaping it further by pool rank on top (unchanged — a fixed base instead of the old scaled-
  input one). **TEST FALLOUT, traced not guessed:** 3 pre-existing RouterTests asserted the very invariant Paul just
  asked to reverse for ARP ("VELOCITY INHERITANCE — every processor takes its output velocity from the input
  source," dated 2026-08-09) — before rewriting their expected values, traced the EXACT fold path for `[ARP →
  HARMONIZE]` (`Router.applyStage`'s `.harmonize` case reads the ONE-NOTE pool `emitDriverNote` seeds from the
  driver's OWN resolved `(note, velocity)`, never the original chord — confirmed by reading, not assumed) to derive
  the correct new expected value (100, the VELOCITY default) for BOTH the dry note and the harmony voice, rather
  than guessing. Renamed + rewrote `testArpInheritsSourceVelocity`→`testArpUsesVelocityControlIgnoringSource`,
  `testChainInheritsSourceVelocityThroughHarmonize`→`testChainUsesArpVelocityControlThroughHarmonize`,
  `testAuditionInheritsSourceVelocity`→`testAuditionUsesVelocityControlIgnoringSource`.
  `testEuclidGeneratorInheritsSourceVelocity` (a different generator, unaffected — Paul scoped this to ARP only) is
  untouched, still green, still asserting the old invariant for euclid. **INTEGRATION NOTE:** this branch's own
  single commit landed a SECOND time this session one commit behind `origin/main` — another worktree's "ARP OCT
  DIRECTION" commit (below) had, in the interim, changed the EXACT SAME formula line (`let oct = octDown ? … :
  octIdx`) this commit's own velocity code sits directly beneath in `arpPick` — a real rebase conflict (adjacent,
  not overlapping, lines), resolved by hand: kept their new oct-direction formula verbatim + this commit's new
  velocity code verbatim, rebuilt + retested green on the combined tree before pushing. **JUDGMENT CALL, flagged:**
  Paul said "1 to 100," read literally as the direct value (not a 1–100 MAPPED onto 0–127) — so a VELOCITY of 100 is
  the ceiling, not "full MIDI velocity" (127); if 127 was actually meant, that's a one-line range change.
  **DEVICE-OWED:** the stacked trio's legibility in one column, VELOCITY audibly ignoring how hard the chord was
  played and only tracking the dial, and the oct-direction + velocity changes not interacting oddly in the same
  render pass.**
- **▶ EUCLID COMET BAR — a REAL glow, not a stack of flat circles (2026-09-30, on `main`; iOS builds; DEVICE eye
  owed). Paul, on-device: "the timing on the animation is great, but it doesn't look as good as it did in the
  preview html. Maybe it's missing the glow?" Correct diagnosis. The Stage 2 build (this same day) approximated a
  glow by layering hard-edged circles of falling opacity underneath each lit element — reads as flat concentric
  rings, not a soft halo, because nothing was ever actually BLURRED; the HTML mockup's look came entirely from CSS
  `box-shadow`/`filter: blur()`, a genuine gaussian blur with no equivalent in the first Canvas draft. **FIX:**
  `euclidCometBar` (GridUI.swift) now uses `ctx.drawLayer { … }` + `GraphicsContext.Filter.shadow`/`.blur` — Canvas's
  real counterpart to CSS box-shadow/blur — for every glowing element: a hit node's flare is now one dot inside a
  `.shadow(color:radius:)`-filtered layer (radius scales with `recede`, the same decay factor as before) instead of
  a second flat circle drawn underneath; the comet's trailing tail is now a blurred (`.blur(radius:3)`) gradient
  stroke instead of discrete hard dots; the comet head itself sits inside its own `.shadow(radius:9)` layer for a
  true glowing halo instead of a plain filled circle. The underlying per-node recede/age math (Stage 2) is
  untouched — only HOW each element is painted changed, not when/how bright. UI-only (GridUI.swift), no test-target
  reach — builds clean, nothing to run off-device for a pure Canvas-drawing change. **DEVICE-OWED:** confirm the
  glow now reads as intended at real panel size/brightness — the shadow radii (3–9pt) and the blur amount are
  first-pass values, tunable if they read too soft/too sharp on the actual screen.**
- **▶ ARP OCT DIRECTION — REDEFINED: DOWN now descends BELOW the held keys, symmetric with UP (2026-09-30, on
  `main`; iOS builds, macOS green incl. 2 updated; DEVICE ear owed). Paul noticed DOWN starts a full octave (or
  more) ABOVE the held keys rather than at them, and asked whether starting AT the held keys and descending was
  practical. It was — and it's a deliberate BEHAVIOUR CHANGE, not an addition (Paul: "I'm currently the only user
  so I don't mind behaviour changes. Go for it."). **OLD semantics:** DOWN opened at the TOP octave (`octaves-1`)
  and came DOWN TO the held register — it never sounded anything BELOW the held keys, only reversed which octave
  each lap of the walk landed in. **NEW semantics, symmetric with UP:** lap 0 always opens AT the held register
  (`octIdx 0 ⇒ oct 0`) for BOTH directions; UP ascends from there (`oct = +octIdx`), DOWN now descends BELOW it
  (`oct = -octIdx`) — `arpPick`'s one-line formula (Derivations.swift) simplified from `octDown ? (max(1,octaves)-
  1-octIdx) : octIdx` to `octDown ? -octIdx : octIdx`. **RANGE SAFETY, checked not assumed:** `arpPick` itself only
  ever guards the UNSHIFTED note against 0…127 before applying the octave offset; the actually-shifted
  `note + 12*oct` is range-checked at every one of the 6 call sites in Router.swift (either directly, or via a
  downstream `base + transpose` check the arp/hold/strum paths already share) — the EXACT same mechanism that
  already silently drops a note UP pushes above 127 now equally drops one DOWN pushes below 0, so going negative
  needed no new guard anywhere. +0 new tests — 2 EXISTING `DerivationsTests` updated to the new expected values
  (`testArpOctDirectionInvertsTheLaps`, `testArpOctaveSpanFullSequence`) rather than left asserting the old
  behaviour. **DEVICE-OWED:** an ARP with OCT DIR=DOWN and 2+ octaves actually sounds the held chord first, then
  descends into the register below it, rather than opening high.**
- **▶ ARP EDITOR — a full layout rework + two new fields, VELOCITY + VELOCITY TILT (2026-09-30, on `main`, `67fb646`;
  macOS 1155 green, iOS builds; DEVICE eye/ear owed). Paul specified the new layout precisely: ARP PATTERN's options
  into two equally-sized rows, SPEED to its right at matching height; OCTAVE + OCT DIR stacked one over the other, to
  the right of ARP FLOW, matching FLOW's height; then LENGTH, VELOCITY, VELOCITY TILT to the right of that, equal
  height among themselves — with VELOCITY and VELOCITY TILT named as NEW features, both wanting a ∿ LFO.
  **LAYOUT:** the 10-entry `arpPatternOptions` table (UP/DOWN/UP-DN/ALT LO/ALT HI/AS PLAYED/RANDOM/RND HI/RAND LO/
  RANDOM ONCE) splits into two 5-chip rows via `arpPatternRow`, reworked to take an explicit SLICE instead of always
  the whole table (its `sel` highlight is now `Int?`, not `?? 0` — a pattern belonging to the OTHER row no longer
  wrongly lights this row's first chip, a real bug the split would otherwise have introduced). Height match against
  SPEED is EXACT ARITHMETIC, not eyeballed: 2 rows×48pt + 1×6pt gap = 102, same as `arpSpeedGrid`'s 3 rows×32pt +
  2×3pt gap = 102. OCTAVES/OCT DIR now stack in one VStack beside FLOW's existing 3-item `segV` (each keeps its own
  label). LENGTH/VELOCITY/VELOCITY TILT are three side-by-side fields, naturally equal height since all three share
  the identical `slider`/`lfoSlider` → `FineSlider` (fixed 30pt) content underneath. **NEW ENGINE FIELDS:** `arpVelScale`
  (0…2, default 1 — a flat multiplier on the picked note's own velocity) and `arpVelTilt` (−1…1, default 0 — favours
  the top (+) or bottom (−) of the held pool). No spec for either existed, so both were modeled on established
  precedent rather than invented from nothing: `arpVelScale` mirrors HARMONIZE's `harmVelScale` (a plain velocity-
  scale multiplier); `arpVelTilt` reuses `Derivations.strumVelocity` VERBATIM (the exact formula STRUM's own `velTilt`
  and CHANCE's `chanceTilt` already established as this codebase's tilt convention), keyed on `rank = pos % count` —
  the SAME ascending-pool-rank index `arpPick` already computes to fetch the note itself (captured once, reused for
  the tilt — no second pool scan). For every pattern except AS PLAYED, `rank` is a true pitch-ascending rank (0=lowest);
  AS PLAYED reads press-order instead (`srcPlayed`, not `srcAscending`), so its "tilt" is by play-order there — an
  honest, disclosed minor difference for that one mode, not a second code path. Threaded through all THREE `arpPick`
  overloads (chanMask-based impl, the `filter:` forwarder, the `for cell:` convenience forwarder) with defaults
  (1, 0) that reproduce the exact prior velocity byte-for-byte (verified: `clampVel` is idempotent on an
  already-legal 1…127 velocity, and `strumVelocity`'s tilt=0 scale is exactly 1). `emitArpRow` resolves both via new
  `effectiveArpVelScale`/`effectiveArpVelTilt` (Snapshot.swift, mirroring `effectiveGate`) and passes them to BOTH
  the chain-driver and standalone `arpPick` call sites. **LFO:** both fields joined `AutoParamField` (the ONE enum
  shared by the per-param ∿ LFO AND the older render-time span-automation) — `settingAuto`/`autoValue`/`unitRange`
  gained the two cases, which is ALSO what makes them span-automation-ramp-able for free, unasked but harmless (same
  shared-enum consequence every prior LFO addition to this enum has had). GridUI's 5-switch LFO-editor recipe
  (`lfoLabelText`/`lfoEndpointControl`/`lfoFmt`/`lfoSeedFrom`/`lfoSetBase`) got matching cases each — caught the
  `lfoSeedFrom`/`lfoSetBase` DEFAULT branches fall back to `p.gate` before writing these in, which would have silently
  seeded/written the WRONG param (GATE, not VELOCITY) had either case been skipped. **`bipolarSlider` gained LFO
  support** (a new optional `lfo target:` param, default nil) — the FIRST bipolar field in the app to get a ∿ button;
  nil renders byte-identical to before (confirmed: `lfoLabelRow`'s own no-lfo branch uses the exact same Text/font/
  opacity bipolarSlider inlined previously), so STRUM's VOL TILT and CHANCE's FAVOUR — the only other callers — are
  unaffected. **CAUGHT BY THE COMPILER, not hand-checked (this session's own standing pattern):** adding the 2
  `AutoParamField` cases broke 2 EXHAUSTIVE switches in `Tests/EffectiveParamsTests.swift` (the 28-key recognition
  list and the 28-entry clamp-bounds table, both bumped to 30) — fixed once the build surfaced them. **A genuine
  self-caught bug pre-push:** the first pass only updated TWO of the three `arpPick` overloads with the new params;
  the THIRD (the `for cell:` convenience one `emitArpRow`'s standalone branch actually calls) was left unchanged,
  which the iOS build failed on immediately (`extra argument 'for' in call` — Swift's overload resolution tried to
  match the call against a different candidate once the intended one no longer matched) — caught by the real
  compiler, not assumed fixed. **INTEGRATION NOTE:** built and committed on a branch that started one commit behind
  `origin/main` (another worktree had just landed EUCLID redesign Stage 1, `481cafe`, unrelated fields/files);
  rebased cleanly (no conflicts — different processor, disjoint field names), rebuilt + retested green on the
  combined tree before pushing, per the standing multi-worktree workflow. **JUDGMENT CALLS, flagged not silent:**
  VELOCITY's 0…2 range/percentage display and VELOCITY TILT's pool-rank tilt basis are this session's own design
  choices (Paul asked for the features + LFO, not their exact semantics) — modeled closely on existing conventions,
  but unverified against what Paul actually pictured; the OCTAVE+OCT DIR stack's height-match against ARP FLOW is a
  best-effort spacing choice, NOT provably exact arithmetic like the PATTERN/SPEED pair — SwiftUI's own per-label
  text-line-height isn't something to hand-derive from source, so this one is real device-eye-owed, not just
  routine caution. **DEVICE-OWED, the whole feature:** the layout at real panel width (5 side-by-side slots in row 2
  is the most cramped row this card has ever had), VELOCITY audibly scaling louder/softer, VELOCITY TILT audibly
  favouring top/bottom notes across a real chord, and both ∿ LFOs sweeping smoothly.**
- **▶ EUCLID REDESIGN — Stage 2 (the UI): four always-visible rows, DIRECTION seg, the merged NOTE SELECT chips, a
  live comet-bar (2026-09-30, on `main`; iOS builds, macOS 1160 green; DEVICE eye owed — no test-target reach,
  GridUI-only, same as every prior playhead/widget change in this file). Completes the redesign Stage 1 shipped
  the model/engine for — planned via a two-round HTML mockup with Paul before any code (comet trail chosen over
  two other candidates; the final row layout ratified in a second round). **THE EDITOR:** `case .euclid:`
  (GridUI.swift) rebuilt entire — the old "single euclid OR a dynamic +ADD LINE stack up to 8" branch is gone;
  `ForEach(p.euclidLinesForEditing().enumerated())` always renders exactly 4 row blocks (the SAME shared helper
  Stage 1's SnapshotBuilder resolve calls, so the editor and the render path can never derive "what the 4 rows
  are" differently). Each row: line 1 = `HITS ◀K▶ OF ◀N▶` · `ROTATE ↻r` · a new `FWD|REV` seg bound to `reverse` ·
  the existing INVERT tap-pill; line 2 = the merged NOTE SELECT (two `euclidNoteSelChipRow`s, sliced from
  `EuclidNoteSel.allCases`'s own declared order — ALL·N1…N8 on row 1, LOW·HIGH·BOT2·TOP2·CYCLE·RANDOM on row 2 — so
  there's no second, separately-maintained grouping list to drift from the enum) to the left, the new comet-bar to
  the right; DIE's dial (kept, not dropped, from the pre-merge editor) reappears inline only when the row's
  resolved noteSel is CYCLE/RANDOM. New `euclidLineEdit4(idx:)` replaces the old `euclidLineEdit` (deleted, no
  callers left) — it seeds/pads to 4 via `euclidLinesForEditing()` before writing, so touching ANY of the 4 rows
  "promotes" the machine to a real 4-line array on first edit, same idiom the old "+ ADD LINE" button used, just
  automatic. Footer keeps GRID (rate) + SPAN (shared machine-wide, unchanged); the footer's ROTATE slot (already
  conditionally hidden in LINES mode pre-redesign) is now unconditionally empty (rotate lives on every row's own
  line 1); the standalone "PICK — for ALL-target lines" row is gone, folded into the per-row selector. **THE COMET
  BAR:** a new non-interactive `euclidCometBar` (`TimelineView` + `Canvas`, ~30fps) — reuses `euclidPhase`/
  `euclidReadIndex` (Derivations.swift, Stage 1), the SAME pure functions the real render path calls for its own
  step math, so the bar can never silently disagree with what's actually heard the way RATCHET PATTERN/DEST once
  did. A glowing dot travels the pattern continuously; each hit node flares and holds a brief decaying afterglow as
  the dot passes; rests stay a plain hollow ring — reads as decoration, never as a tappable grid (per Paul's "I
  don't want this to look selectable"). **TWO DELIBERATE DEVIATIONS FROM THE LITERAL APPROVED MOCKUP, flagged
  plainly rather than silently changed:** (1) NOT swing-warped — the mockup obviously couldn't show this either
  way; matches every OTHER pattern-processor's live sweep in this exact file (BURST/RATCHET/TUTTI/DEST's
  `StateMatrixClock`/`liveCol` also read a plain linear beat, only the real render path applies `musicalOf`) —
  threading swing into this ONE new widget would need a new stored property on `ProcessorBox` for a discrepancy
  that only shows at non-50 swing settings; scoped out rather than half-built. (2) the comet's direction of travel:
  the mockup showed BOTH the displayed hit pattern mirroring AND the comet visually reversing to run right-to-left
  under REV; built instead so screen position always shows the i-th step in PLAYBACK order (`euclidReadIndex`
  resolves which buffer index that is) and the comet ALWAYS travels left-to-right — steadier, more legible, and
  actually reads as "impressive" (Paul's own word for the brief) rather than as a glitch, which a direction-
  reversing comet risked once actually animated rather than sketched in static HTML. **DEVICE-OWED:** whether
  deviation (2) reads right in practice — reverting to a direction-flipping comet is a small, contained change if
  Paul prefers the literal mockup once he sees the real animation; the chip legibility at real panel width (up to
  15 options across 2 rows); the comet bar's height/proportions next to a 2-row chip stack; the flare/afterglow
  timing constants (0.02 threshold, 1.5-step decay window — all tunable, unverified off-device); confirm an old
  saved doc (flat single-euclid, or a pre-redesign 2-8-line doc) opens showing its content correctly across the 4
  rows with no data loss for the first 4 lines.**
- **▶ RECEIVER TOGGLES + DOOR PICKERS — the note-name/key/"no input" text shrunk 15pt→11pt (2026-09-30, on `main`,
  `ad48901`; iOS builds; DEVICE eye owed). Paul: reduce the size of the text showing notes on the receiver toggles
  and related instances. That readout (`buildReceiverSelectChip`'s `big` label — key ?? live notes ?? "no input")
  was rendering at `buildIOSelectChip`'s shared 15pt: fine for a single letter, but a short live-note string
  ("c e g") rarely needs `minimumScaleFactor`'s shrink-to-fit to avoid clipping, so it rendered near the full
  nominal size and read as too dominant for a 2-3 char label. **FIX:** `buildIOSelectChip` gained a `textSize:
  CGFloat = 15` param — the receiver-chip call site passes 11; `buildEmitterToggles`' call (the MIDI-OUT bus-letter
  chips) passes nothing, keeping its plain "A/B/C/D" at the original 15 — Paul scoped this note-display feature to
  receivers specifically in an earlier session ("not the separate MIDI-OUT emitter toggles"), so I left emitter
  toggles untouched here too. Matched the same 11pt directly on `ioChip` (GridUI.swift) — the shared sibling that
  gives ECHO's FROM, CHORDS' SCALE FROM, and AVOID's WHICH INPUT the identical note-display styling per the
  2026-09-29 receiver-door-picker audit — since its own doc comment already commits to "keep the two visually in
  sync by hand if the shared look ever changes." UI-only (BuildPage.swift/GridUI.swift), no test-target reach.
  **DEVICE-OWED:** legibility of the smaller text at real chip size, both for a short note label and for a longer
  one like a key name ("D MIXOLYDIAN") still relying on the auto-shrink floor underneath the new, smaller base.**
- **▶ BUILD UNDO — structural chain edits now ALWAYS get their own step (2026-09-29, on `main`, `f49363b`; iOS
  builds, macOS 1155 green; DEVICE-owed — no test-target reach, UI-state bookkeeping only). Paul: "I added two
  processors to the MIDI chain, then hit undo and both disappeared. Every user touch action should have a
  corresponding undo/redo step." **ROOT CAUSE, traced not guessed:** `buildApplyChain` is the SINGLE funnel every
  chain mutation goes through — add/remove/move/type-change/bypass-toggle AND per-param slider drags alike — and it
  unconditionally called `buildRecordUndo("chain")`. That coalesce key exists so a FineSlider's dozens-per-second
  `onChanged` ticks collapse into one undo step (confirmed by reading `FineSlider`'s `DragGesture.onChanged` — it
  really does call `set(v)`, and therefore `buildApplyChain`, on every tick) — but the SAME blanket key was applied
  to genuinely discrete, one-shot actions too. So "add processor A" pushed a checkpoint and set `buildUndoKey =
  "chain"`; "add processor B" right after saw that key already active and silently skipped recording — both adds
  shared ONE undo step, and a single undo dropped both at once, exactly Paul's report. **FIX:** `buildApplyChain`/
  `buildChainEditSlot` now take an explicit `coalesce` override (default `"chain"`, preserving the param-drag
  path). The five DISCRETE call sites — `buildChainAddCard` (ADD), `buildChainRemoveSlot` (DELETE, both the editor
  button and drag-to-trash), `buildChainMoveSlot` (drag-to-reorder — confirmed fired only once, from `.onEnded`,
  never per drag-frame, so forcing it fresh can't explode the stack), `buildChainSetType`, `buildChainToggleBypass`
  — now pass `coalesce: nil`, which `buildRecordUndo` treats as "always push, no coalescing," regardless of what
  `buildUndoKey` currently holds. **ALSO:** added a 0.6s SLIDING TIME WINDOW to "chain" coalescing specifically —
  the generic param-mutate path (`onEdit`, used by sliders AND plain discrete taps like a segmented MODE picker
  alike, since nothing at that boundary can tell them apart) still shares one key, so two genuinely separate
  "chain" edits could still merge if nothing else intervened between them. Now a same-key coalesce only continues
  if the last one was < 0.6s ago (refreshed on every continuation, so a slow multi-second drag still stays one
  step throughout); a tap that lands well after a drag has clearly ended gets its own step. **DELIBERATELY SCOPED
  to "chain" only** — checked `buildRecvEdit`'s own doc comment first ("coalesced into one 'recv' burst so a run of
  config tweaks is a single undo," an explicit, documented design choice from 2026-08-27) and left "recv"/
  "randomize"/"mutate" on their original untimed behaviour, so a deliberate multi-tap MIDI-config session still
  collapses to one undo exactly as designed — a blanket time window would have silently broken that. Verified
  every `buildApplyChain`/`buildChainEditSlot` call site by grep (4 total) before and after, confirming none were
  missed and no other caller needed the same treatment. **RESIDUAL, flagged not fixed:** two truly discrete param
  taps on DIFFERENT controls within the same open editor, performed within 0.6s of each other, can still coalesce
  into one step — an accepted, narrow edge case (see the comment on `buildRecordUndo`), not the reported bug.
  DEVICE-OWED: confirm two back-to-back ADD/DELETE/REORDER/BYPASS actions each undo independently, and that a
  normal slider drag still collapses to one undo step (not one per tick).**
- **▶ EUCLID REDESIGN — Stage 1 (model/engine): TARGET+PICK merged into one NOTE SELECT field, DIRECTION (FWD/REV),
  always-exactly-4-lines (2026-09-30, on `main`; iOS builds, macOS 1160 green incl. 5 new). Paul asked to redesign
  the EUCLID editor UI — planned via a two-round HTML mockup (three hit-bar candidates, comet trail chosen; then the
  final row layout) before any code, per the plan at `~/.claude/plans/velvet-foraging-curry.md`. This is the
  model/engine half; the UI half (Stage 2 — the new row layout, the comet-bar widget, the merged chip selector) is
  still to come. **THE MERGE:** `EuclidLine.target` (0=ALL/1-8=N1…N8, which chord note a line fires from) and `.pick`
  (ALL/CYCLE/LOW/HIGH/RANDOM, only meaningful for TARGET=ALL) collapse into ONE new `EuclidNoteSel` (String-raw enum,
  ALL·N1…N8·LOW·HIGH·BOT2·TOP2·CYCLE·RANDOM — BOT2/TOP2 ported from the sibling EUCLID MASK's own `MaskChordPick`).
  `target`/`pick` are KEPT on `EuclidLine` for decode compatibility (never read by the render path again); a new
  `noteSel: EuclidNoteSel?` is additive-Optional (the same CR-8 reasoning already recorded for `die`). **BOT2/TOP2
  needed a real engine change** — `strikeChord(onlyIndex:)` only ever strikes one pool rank or the whole chord;
  `runEuclidLine` now resolves a `noteSel` to either an `onlyIndex: Int?` or a `(lo,hi)` range, calling `strikeChord`
  once per index in the range when one applies — mirroring EUCLID MASK's own `maskChordPickRange` loop rather than
  inventing a second mechanism. **DIRECTION (FWD/REV):** a new `reverse: Bool?` on `EuclidLine`. REV mirrors
  (time-reverses) the K-of-N pattern by flipping the READ INDEX into the already-ROTATE-baked buffer
  (`euclidReadIndex(step,n,reverse) = reverse ? n-1-step : step`), NOT by rebuilding the buffer with a second
  rotation — verified algebraically that rotate-then-reverse and reverse-then-rotate are NOT the same pattern in
  general (they differ by a shift of 2×rotate mod n, coinciding only at rotate=0 or n/2), so this is a deliberate,
  tested composition order, locked by a worked-example `DerivationsTest` rather than left to chance. Every buffer
  read in `runEuclidLine` — the hit/rest test AND the `hitsUpTo` ordinal loop CYCLE/RANDOM use for their walk
  position — goes through the same `euclidReadIndex`, so a reversed line's pick-walk stays correct in PLAYBACK
  order, not buffer-storage order. **ALWAYS EXACTLY FOUR LINES** (the fixed-4-row redesign, replacing "start with
  one euclid, tap +ADD LINE up to 8"): `SnapshotBuilder`'s old `.prefix(8)` clamp is gone — `MachineParams.
  euclidLinesForEditing()` (Models.swift, shared by SnapshotBuilder AND the eventual Stage-2 editor, so the two
  can't independently derive this differently) always returns exactly 4, deriving row 0 from the flat single-euclid
  fields when untouched (rows 1-3 silent, `pulses: 0`) or padding/truncating a touched `euclidLines` array to 4 —
  **a deliberate, disclosed consequence: any existing saved session that used 5-8 lines loses lines 5-8 permanently**
  (Paul: "fixed at four always visible rows, please" — named here plainly, not silently absorbed). Router.swift's
  `.euclid` case dropped its `euclidLines.isEmpty ? flat : lines` branch entirely — always `for L in p.euclidLines`.
  **A MIGRATION SUBTLETY caught before it shipped wrong:** a pre-redesign line with `pick == nil` fell back to the
  MACHINE-WIDE global `euclidPick` (the old "PICK — for ALL-target lines" row) — a fallback `EuclidLine.
  noteSelResolved` can't see on its own (it only knows its own fields). Fixed by resolving this WITH the full
  context inside `euclidLinesForEditing()` itself (which has `self.euclidPick`), not left to the narrower per-line
  computed property — regression-tested (`testEuclidLineWithoutItsOwnPickFallsBackToTheOldMachineWideGlobal`).
  **TWO REAL BUGS CAUGHT BY THE TEST SUITE, not by inspection — this session's own standing rule, twice over:**
  (1) a first draft tried to make the render path's step computation and the eventual Stage-2 UI comet-bar share
  ONE formula (`euclidPhase`, a continuous phase-in-[0,n) function) — mathematically proven equivalent to the
  original exact-integer step math for real-number arithmetic, but in FLOATING POINT the continuous version's extra
  divide+floor+multiply round-trip introduced a rare off-by-one at tick boundaries that the original integer-only
  path never had. Caught by `testEuclidPulsesFromPoolTracksHeldCount` (an existing test, not a new one) going 9→54
  note-ons — traced with a throwaway debug print rather than re-guessing by hand, per this project's own standing
  technique. Fixed by reverting `runEuclidLine`'s own step math to the original exact Int64 formula and keeping
  `euclidPhase` as a SEPARATE, UI-only function (Stage 2) — a discrete hit/rest decision needs exact integer ticks;
  a comet's visual position tolerates float imprecision invisibly, and the two shouldn't share a code path just
  because they share a CONCEPT (the same rate/span/anchor reading). (2) even after that revert, the SAME test still
  failed the same way — traced (again via a debug print, not guessing) to a genuine interaction the redesign
  introduced: `iterateTicks` dedups via a `lastTick[row]` scalar SHARED across every line on a row (safe for one
  real line; a pre-existing, undisclosed limitation for 2+ real lines sharing a row across a render-window boundary
  — not introduced here, just newly exercised). Running all 4 lines unconditionally under `HITS FROM: POOL` (which
  overrides EVERY line's K to the held-note count, ignoring each line's own authored `pulses`) turned the 3
  always-present silent padding rows into 3 MORE real, identical lines competing for that shared dedup state across
  the ~24 render windows a 2-beat test spans. Fixed by skipping any line with `pulses <= 0` entirely (`for L in
  p.euclidLines where L.pulses > 0`) — an unused fixed row now stays silent regardless of POOL, matching the
  approved mockup's own "row 4 — 0 hits, no comet" idle-state language, and keeps genuinely-authored multi-line
  polyrhythms (2+ real lines, already supported pre-redesign) working exactly as before. **ALSO FIXED, found while
  testing:** the render-time SPAN-AUTOMATION system (`AutoParamField.euclidPulses/.euclidSteps/.euclidRot`,
  `SnapParams.settingAuto`) mutates the FLAT `euclidPulses`/`euclidSteps`/`euclidRot` fields per render window — but
  since Router.swift no longer reads those flat fields at all, an AUTO lane ramping EUCLID's hit count silently
  stopped reaching the render path. Fixed by mirroring `settingAuto`'s write onto `euclidLines[0]` (row 0 — the row
  the flat fields always fed) alongside the flat field, caught by the EXISTING
  `testRenderAutoPassSpanRampsHitsUpAcrossBars` test, not a new one. **TESTS:** +5 (a worked-example composition-
  order lock for REVERSE; BOT2/TOP2 strike two notes; REVERSE genuinely time-reverses the onset sequence, not just
  a cosmetic relabelling; always-exactly-4 resolution for both a flat doc and an old 2-line doc; the machine-wide
  PICK fallback). Every pre-existing EUCLID test (LINES polyrhythm/target, per-line PICK/DIE, POOL, SPAN, INVERT,
  CYCLE/RANDOM, chain-driver composition) passes UNCHANGED — confirming the redesign's migration path is genuinely
  byte-identical for every pre-existing document shape. No UI touched yet — GridUI.swift is next (Stage 2).
  **DEVICE-OWED (once Stage 2 ships):** none yet — this stage is pure engine/model, fully covered by the macOS test
  target, nothing device-only to verify until the UI lands.**
- **▶ SELECT GRID — a live scrolling piano roll on the auditioning cell (2026-09-29, on `main`; iOS builds, macOS
  1155 green; DEVICE eye owed). Follow-through on the PART ROW ROLL entry below: Paul asked for the SAME accuracy
  standard (true onset beats read live from the render engine, velocity reflected, "no shortcuts") on the SELECT
  grid's currently-auditioning cell — but with a DELIBERATELY different, explicitly-requested motion model: notes
  SCROLL right-to-left as they play, not PART's fixed-column fade-in-place. Also folded in a small earlier fix that
  hadn't been logged yet: `partRollFadeBeats` doubled 2.0→4.0 beats per a same-day follow-up ask ("increase the time
  for the fade"). **ROOT STATE, confirmed by tracing (not assumed):** the SELECT grid's existing roll is entirely
  STATIC — every present cell, including the selected/auditioning one, draws through `buildGridSelPianoRoll` →
  `buildOutputFace` → `roomsRibbonFace`, a one-shot `Canvas` render from an OFFLINE-simulated note array
  (`gridSelRollBars` → `Dice.runRecorder` against a fixed standard chord, not the cell's real live output). Its
  `playing`/`strikeIdx` params are dead — explicitly neutered in the 2026-09-08 "calm cells" rewrite ("kept for
  call-site compatibility but ignored"), confirmed via a targeted trace before building anything. So this was new
  code, not a matter of flipping an inert switch. **ENGINE:** none — reuses `Router.rowSoundingVoices()` verbatim,
  the same primitive the PART roll introduced, scoped to the ONE engine row the chain audition already pins to
  (the existing `buildChainAuditionRow`). **DATA:** a new reconciliation block in the existing `.onReceive
  (meterTimer)` (AudioUnitViewController.swift), a third sibling right after the PART ROW ROLL block, mirroring its
  exact diff/freeze/prune technique (poll → diff against last-seen held notes → freeze `heldToBeat` on release →
  prune once fully receded) but scoped to a single row via a new `meters.selectRollNotes: [PartRowRollNote]` (plain,
  non-`@State`, same reason as `partRollNotes` — the TimelineView-driven Canvas re-reads it on its own per-frame
  schedule, so a SwiftUI-invalidating write would be pure waste). Gated on `ddSolo` (`buildVoiceOwner == .chain`,
  the precise "is a SELECT cell genuinely the live voice" check) AND a selection present — NOT the `selGrey` UI
  proxy alone, so a selected-but-stopped cell correctly reports no live notes rather than a stale/wrong snapshot.
  **DRAWING:** new `buildSelectLiveRoll(tint:)` (BuildGridSelector.swift) — right edge = now, left edge =
  `selectRollWindowBeats` (new constant, 2.0 — a SELECT cell is one grid column, not a whole PART row, so
  meaningfully less horizontal room than PART's context; flagged as a tunable default, same as `partRollFadeBeats`
  itself was tuned live off device feedback this session) beats ago. A note's HEAD (onset, or `heldToBeat` once
  released) and TAIL (true onset beat) each map independently via `x = clamp(w×(1−age/window), 0, w)` — a
  STILL-SOUNDING note's head stays pinned at the right edge while its tail scrolls left as it's held (grows to fill
  the cell on a long hold, the scrolling analogue of PART's "head tracks the live position"); a RELEASED note's
  whole bar keeps scrolling left and exits off the left edge — the deliberate difference from PART (which freezes a
  released bar in place and only fades its opacity). Added a soft opacity fade as a bar's head nears the left edge
  (`edgeFade`) so the exit isn't an abrupt pop — the scrolling context's equivalent of PART's own recede factor, same
  "no shortcuts" rigor applied to a different problem. A minimum-visible-width floor mirrors `roomsRibbonFace`'s own
  `max(x0+2, x1×w)` — without it a very short/instantaneous strike computes a zero-width, invisible rect and
  silently never renders, exactly the kind of shortcut this task ruled out. No `musicalOf` swing-warp needed (unlike
  PART, which reconciles against a separate swing-warped playhead) — there's no second visual element on a SELECT
  cell to stay in sync with, so the raw true onset beat is the most direct, most accurate signal to draw from.
  Reuses `roomsRibbonFace`'s own thickness/opacity formulas (`2.0+vel×2.5` thickness, `0.4+0.5×vel` opacity) so the
  switch from the idle static ribbon to the live view doesn't jump in visual weight, and `rollLaneForPitch`
  (Derivations.swift) verbatim for the pitch→lane mapping. **WIRING:** in `buildGridSelCell`, `selGrey && ddSolo`
  now branches to the live roll instead of the static `buildGridSelPianoRoll` call; every other case (idle,
  selected-but-stopped, committed, or a non-SELECT caller of the same shared function) is byte-identical to before
  — a selected-but-stopped cell keeps its static offline preview rather than an empty live canvas, the natural
  low-risk fallback. Colour needed no new work: `rollTint` already resolves to `Color(white: 0.22)` (dark ink) for
  this state, correct as-is since `selGrey`'s background is the light `buildSelectGrey` — the opposite contrast
  problem from PART's dark cells, and already solved. Planned first (EnterPlanMode, one Explore pass confirming the
  static/dead-param state, a second targeted Explore pass locating the exact `meters.partRollNotes`/`roomsPart-
  NoteRoll` code to mirror precisely rather than re-derive from memory) before any code. UI-only, no
  `Router.swift`/engine change, no macOS test-target reach (GridUI-only, matching every prior playhead/roll fix this
  session). **DEVICE-OWED:** the scroll reads smooth and beat-locked, not jittery; a long-held note visibly fills
  the cell rather than looking stuck; the exit fade is soft, not a pop; `selectRollWindowBeats = 2.0` is legible at
  real cell size for typical chain content (arp density especially) — first tunable to revisit if too cramped or
  too sparse; the dark-ink colour still reads with enough contrast against the light `selGrey` face.**
- **▶ RECEIVER-DOOR PICKERS — a codebase-wide audit + unification with the main toggles (2026-09-29, on `main`,
  `dbf3fa3`; iOS builds; DEVICE eye owed). Paul: "please review everywhere in the code where another receiver
  toggle is used, for things like chord and echo. I want the styling and dynamic note info to be the same as on the
  main toggles." Audited every A/B/C/D-style picker across GridUI.swift/RackMatrix.swift and classified each as
  RECEIVER (MIDI-IN door reference, in scope) or EMITTER (MIDI-OUT bus reference, out of scope — Paul named
  "receiver" specifically): DEST's "EMITTER PER STEP", DEAL's "EMITTER 1/2", MUTE MATRIX's per-column mute row, TAP's
  "TO — where the copy exits", HOCKET's "LISTEN TO — the wire" (another ROW's OUTPUT, not an input door — "put it on
  a later row than what it listens to"), and the whole of RackMatrix.swift ("THE RACK — the emitter treatment
  matrix") are all EMITTER-side, untouched. Found exactly THREE genuine receiver-door pickers beyond the main
  toggles, each a hand-rolled or plain `seg()` control with none of the main toggles' styling or live-note behavior:
  **ECHO's "FROM"** (`echoInKeyReceivers`, a multi-select bitmask — which door(s) define "in key" for the pitch-step
  trail), **CHORDS' "SCALE FROM"** (`chordsScaleRef`, single-select + "—"/none — which door supplies the key; its own
  comment already said "the KEY is read from a RECEIVER set to SCALE" — this ALSO fixes the CHORD DOOR's own "KEY
  FROM" pop-up for free, since that door mounts this exact CHORDS processor editor, per the door's original
  design), and **AVOID's "WHICH INPUT"** (`avoidRefIndex`, single-select, shown only when `avoidRefKind == .door` —
  "another MIDI input's live notes" per its own comment). **THE REFACTOR:** `ProcessorBox` (GridUI.swift) is a
  SEPARATE `View` struct from `DiagView` (BuildPage.swift's main type) — it can't call `DiagView`'s own
  `buildIOSelectChip` method directly (no shared `self`). Rather than thread `DiagView`'s full state through
  `ProcessorBox` or risk touching the two already-shipped, heavily-used main toggles, extracted two NEW top-level
  free functions (GridUI.swift, beside `receiverGrey`): `ioChip(_:on:accent:action:)` — the bare visual core (text/
  background/border/tap), a deliberately smaller sibling of `buildIOSelectChip` that leaves out its chase-index
  "invite" animation and long-press "apply to every row" gesture (both `DiagView`-only `@State`, and both concepts
  that don't apply to a per-processor door reference — ECHO/CHORDS/AVOID aren't rows); and `noteClassLabel(_:)`, the
  shared lowercase/no-octave formatter, which `BuildPage.swift`'s own `liveNoteClassLabel` now calls too (was
  standalone duplicate logic, now one implementation). New `ProcessorBox.doorKeyLabels: [String?]` (mirrors the
  EXISTING `avoidInputNotes` pattern exactly — a per-door array, populated at the ONE real call site that already
  supplies `avoidInputNotes`, `buildSlotBox`'s `ProcessorBox(...)` — every OTHER `ProcessorBox` call site (tab
  strips, the chord-sequencer popup) falls back to its all-nil default, same as `avoidInputNotes` already does
  there, so this isn't a new gap). All three pickers now compute their chip label identically to the main toggles:
  `doorKeyLabels[i] ?? noteClassLabel(avoidInputNotes[i]) ?? "no input"`. CHORDS' "—" (none) option — no separate 5th
  widget; tapping the already-selected door deselects it, matching what the old 5-way seg offered with one fewer
  control. **FLAGGED, not fixed:** `buildIOSelectChip`'s own `top:` parameter is genuinely dead (its two-line design
  was flattened to one line back on 2026-08-30 and the parameter was never removed — confirmed while reading the
  function closely) — left alone as out-of-scope housekeeping, not touched by this pass. **DEVICE-OWED:** the three
  reworked editors' legibility/layout at real panel size, and that CHORDS' new deselect-by-re-tapping interaction
  reads as intentional rather than broken.**
- **▶ PART ROW ROLL — three device-reported fixes: note contrast, blinking→fading, and a REAL pre-existing playhead-
  jitter bug (2026-09-29, on `main`, `0eb862b`; iOS builds; DEVICE eye/ear owed). Paul, testing the new live piano
  roll: the note colour needs more contrast, the playhead jitters when stopped, and notes are blinking out rather
  than fading. **CONTRAST:** the note colour was the row's raw, unmixed hue — the SAME colour family as the cell's
  own background tint (`partFerryFill` mixes that identical hue into the dark ground), so at typical fade opacity
  the bars barely stood out. Now blends the hue 55% toward white (`mixHex(partFerryHue(r), 0xFFFFFF, 0.55)`) so
  notes read as bright marks over the darker, more saturated background — the same "notes pop white-ish over a
  coloured cell" language already used elsewhere in this grid. **BLINKING, ROOT CAUSE:** a released note's
  `heldToBeat` FREEZES at its release point, but the draw code only ever varied opacity by POSITION within the bar
  (distance from the frozen head) — never by how much REAL TIME had passed since release. So a released note held
  CONSTANT brightness frame after frame (nothing in the per-segment gradient depended on `live` once frozen), then
  vanished in a SINGLE FRAME once its age crossed `partRollFadeBeats` and the existing `guard` dropped it — a blink,
  not a fade. Fixed by adding the missing piece: a `recede` factor (`1 − (live − headBeatRaw) / partRollFadeBeats`,
  clamped 0…1) multiplied into every segment's opacity — continuously dims the WHOLE bar as time passes since
  release, reaching 0 exactly as the guard's cutoff arrives, so by the time a note is actually dropped it's already
  invisible. A still-sounding note (`heldToBeat == nil` ⇒ `headBeatRaw == live` always) keeps `recede == 1`,
  unaffected — this bug was specific to released notes. **PLAYHEAD JITTER — a genuine, pre-existing bug, not
  something new in the roll's own code, just made newly obvious by it:** traced `meters.syncBeat`
  (AudioUnitViewController.swift) — its own doc comment says "only HARD re-anchor on a genuine discontinuity...
  otherwise FREE-RUN... so 4Hz sampling jitter never shows," but its ONE call site was passing `playing: nd.playing`
  (the HOST's raw transport state) instead of `nd.effectivePlaying` (host OR free-run). During FREE-RUN (a ferry/
  part driving its own clock while the host transport is genuinely stopped — the normal way to audition a part
  without the host DAW running), the host is NEVER "playing" by definition, so `!playing` was PERMANENTLY true,
  defeating the dejitter guard entirely and hard-re-anchoring the beat on EVERY 4Hz poll — exactly the "~4Hz
  sawtooth" the original 2026-09-11 dejitter fix (`ef48264`) was built to kill, just scoped specifically to
  free-run playback (steady host-driven playback was never affected, which is why this went unnoticed until a
  new, low-motion-tolerant view — the roll — made the creep-then-snap pattern obvious). Fixed by passing
  `nd.effectivePlaying` instead — `nd.beat` was ALREADY the correct "effective" beat (per Kernel.swift's own
  comment), only this one boolean was reading the wrong field. **SECOND, RELATED BUG found in the same pass:** the
  `@State d` refresh trigger (`if nd.playing != d.playing || nd.tempo != d.tempo || nd.pass != d.pass { d = nd }`)
  never checked `effectivePlaying` — since `nd.playing` stays `false` throughout an ENTIRE free-run session by
  definition, `d.effectivePlaying` could go stale INDEFINITELY unless tempo/pass ALSO happened to change at the
  same moment, desyncing `roomsPartPlayhead`/`roomsPartNoteRoll`'s own visibility gate from the TRUE free-run state.
  Added `effectivePlaying` to the trigger condition. UI/telemetry-only changes — no Router/engine touch, no new
  tests (GridUI/AudioUnitViewController have no macOS test-target reach, same as every prior playhead fix in this
  file); iOS build green. **DEVICE-OWED:** the note colour actually reading with enough contrast; a held note
  visibly fading out smoothly rather than popping; and — the one most worth confirming carefully — the sweep/roll
  staying rock-steady during a FREE-RUN part (host transport stopped, a ferry playing on its own), not just during
  host-driven playback.**
- **▶ ECHO — a live in-key pitch-step via ABCD receiver toggles, replacing the confusing POOL mode (2026-09-29, on
  `main`, `d092d9b`; macOS 1151 green incl. 7 new, iOS builds; DEVICE ear/eye owed). Paul: each echo repeat should be
  able to step to the NEXT IN-KEY note (up if PITCH STEP is positive, down if negative — sign only, magnitude no
  longer matters in this mode) instead of a flat semitone amount, where "in key" is read from whichever of the 4
  receivers are toggled — and it must be genuinely LIVE ("I want it live, please"): a chord change on the referenced
  receiver(s) mid-tail bends the walk, each repeat chaining from the PREVIOUS repeat's actual landed pitch, never a
  fixed offset from the source note. Also: remove the old POOL pitch-step mode entirely ("I saw pool but didn't
  understand what it did") — replaced by ABCD multi-select toggles, not a single receiver picker. Planned carefully
  first (EnterPlanMode, 2 parallel Explore agents + 1 Plan-agent validation pass, re-entered plan mode after the user
  asked "is this clear instruction?" surfaced real ambiguity) before any code — the validation pass caught two real
  bugs pre-implementation: (1) a same-window multi-repeat staleness bug (`drainEchoTails` takes `let e =
  echoTails[i]` ONCE before its `for k in 1...e.repeats` loop — reading the walk cursor through `e` inside that loop
  would have two same-window repeats both read the same stale value instead of chaining), fixed by seeding a LOCAL
  `var` cursor once per tail per drain call, read/written through the loop directly, with the array write-back only
  feeding the NEXT render window's drain call; (2) inferring "in-key mode engaged" from `inKeyReceivers != 0` would
  have made "IN-KEY mode with zero receivers ticked" indistinguishable from "mode not engaged," silently falling
  back to flat semitones instead of the required "hold at last landed pitch" — fixed with an explicit `inKeyMode`
  flag on the tail, not an inferred one. **ROOT ENGINEERING PROBLEM: `EchoTail` was fully static once pushed**
  (every field written ONCE at `pushEchoTail` time; the only prior cross-window mutation was `active` flipping
  false on retirement) — going live meant adding the FIRST genuinely mutable per-tail field,
  `inKeyLast` (the walk cursor). Disclosed as a sanctioned, narrowly-scoped exception to the engine's derived-never-
  accumulated rule, same class as `riffDrunkPos` — but structurally SAFER than that precedent: it's per-tail (not
  per-cell/session-long), and provably exempt from the seek/loop replay concern DRUNK carries, because a tail cannot
  survive a beat discontinuity at all (`clearEchoTails` fires first) — and its reset is FREE, not a separate
  mechanism, since `pushEchoTail` always fully reconstructs the struct via a literal rather than in-place mutation,
  so a reused slot's `inKeyLast` silently defaults back to unset. New `nextInKeyNote` (Derivations.swift) always
  advances to a genuinely DIFFERENT note — unlike the existing `keyFilterNote` (AVOID's own primitive), which snaps
  to nearest-or-stays if the input is already in-key; the new function's whole point is that even an already-in-key
  note must still move. Live reads reuse `doorRefMask` (already proven safe to call from this exact render-window
  context by AVOID) unioned across whichever ABCD receivers are toggled, mirroring AVOID's own `.sounding` union.
  **SCOPE GAP FOUND DURING IMPLEMENTATION, inherited unchanged from the old POOL mode, not a new regression:** tracing
  `emitEchoColumn`/`isEchoTail` mid-implementation revealed THREE separate echo-tail registration call sites, not
  one — `registerEcho` (single-slot `[ECHO]` or an upstream-then-echo tail like `[HARMONIZE→ECHO]`), `pushEchoForNote`
  (a hold-chain shape like `[ECHO→HARMONIZE]`, echo NOT last), and `registerLengthChainEcho` (`[ECHO→…→LENGTH]`
  specifically). POOL mode's own `echoPoolMask` computation only ever existed in `registerEcho` — confirmed via grep
  before assuming — so IN-KEY mode, threaded the same way, inherits the identical scope: it works for ECHO standalone
  or as a chain's own tail, not for the other two shapes. CHAIN route is architecturally inapplicable to `registerEcho`
  regardless (nothing sits downstream of ECHO when it IS the tail) — so "IN-KEY × CHAIN route" was never a reachable
  combination to begin with, not a gap. Flagged here plainly rather than silently shipped. +1 DerivationsTest
  (strict-advance / cross-octave / empty-mask / dir-zero / range-exhaustion, mirroring `testScalePitchClassMask-
  AndKeyFilterDirections`'s style) +6 RouterTests (chained walk stays in the reference's pitch classes; genuinely
  live — a receiver's content changed BETWEEN repeats via a manual per-window `process()` loop, not the shared
  `run()` helper, which only takes one fixed pool for its whole run; empty-mask hold; zero-receivers hold, not a
  flat climb — caught a test-writing mistake of its own: holding also lands on note 60, so filtering `note != 60`
  to isolate "the repeats" from "the dry strike" silently emptied the result — fixed by checking event COUNT
  separately from note VALUE; same-window multi-repeat chaining, the direct regression test for bug (1) above, via
  one oversized `frameCount` so 3 repeats resolve inside a single `drainEchoTails` call; walking a harmonized
  upstream set through `registerEcho`'s own chain-composition branch). One existing test for the removed POOL mode
  deleted outright (`Tests/AcceptanceTests.swift`, nothing left to assert once the mechanism is gone — its
  `Accept.notesA` oracle also can't express a separate referenced receiver anyway); the `FuzzTests.swift` POOL
  randomizer now hammers the new mode instead, including the empty-mask "hold" edge case across all 16 receiver-
  mask combinations. Old saved sessions using POOL decode fine (Codable ignores the removed key) but now play flat
  semitones instead of a pool-stepped trail — a real, silent musical change on next load, expected given the
  removal request, named here rather than left implicit. Plan: `~/.claude/plans/velvet-foraging-curry.md`.
  **DEVICE-OWED:** the walk audibly following a changing chord on the referenced receiver(s) in real time; the
  empty-mask hold reading as a hold, not a dropped/stuck note; the new FROM row's chip legibility next to PITCH STEP.**
- **▶ RECEIVER STRIP — the top label now shows LIVE notes received, not the channel filter (2026-09-29, on `main`,
  `92ed1c8`; iOS builds; DEVICE eye owed). Paul: change the receiver toggles' labels to show the notes being
  received in realtime, but leave whichever one is set to KEY still showing the selected key. `buildReceiverControl`'s
  TOP button (the ENABLE toggle, `buildRecProminent`) previously showed `recChanLabel` — OMNI/CH n/CH ×k, the channel
  filter. Replaced with `recLiveLabel(i, rec)`: for a door in SCALE mode (the standing "key" reference doors like the
  D→SCALE door use throughout this rig) it shows the selected key ("D MIXOLYDIAN", the exact `\(names[root])
  \(type.label)` format the scale pop-up's own ACTIVE summary already uses, for consistency); every other door shows
  its currently-held/received pitches live, e.g. "C4 E4 G4" — reusing `recvHeldNotes` (`AudioUnitViewController.
  swift`), the SAME already-live per-door note feed that already drives the config-sheet REPLAY roll, the IN-piano
  truth-strip, and the AVOID piano — no new polling, no new engine plumbing, just a new reader of state that was
  already being kept current every render. Empty (nothing held) shows a plain "—" rather than going blank. Checked
  why SCALE needed the special case rather than falling through: `recvHeldNotes` for a scale door already reports
  ITS OWN resolved pool (per the AVOID-piano comment on that field: "armed/scale doors report their pool"), not a
  live performance — showing that as "notes received" would be misleading (a wall of 7+ pool notes, not what's
  actually playing), so the key name is the more honest realtime-ish readout for that one door type. Chose the check
  as `rec.doorModeResolved == .scale` (not hardcoded to a specific door letter) so it naturally covers however many
  doors are actually configured as scale references, not just an assumed one. Channel-filter info isn't lost, just
  relocated — it's still reachable via the spanner → MIXER sheet, same as before. Removed a now-stale doc-comment
  that described the old channel-caption behaviour and was left orphaned above the new function. UI-only (BuildPage.
  swift), no test-target reach, matching every prior GridUI/BuildPage-only fix in this file. **DEVICE-OWED:** legibility
  of a real chord's worth of note names at this button's actual size (`.minimumScaleFactor(0.6)` auto-shrinks, same
  as every other label on this button, but untested against 4+ simultaneous notes); confirm a CHORD-mode door (left
  on the live-notes branch, not special-cased like SCALE — Paul only named "key") reads sensibly showing its own
  resolved chord rather than looking broken.**
  **WRONG CONTROL — REVERTED + REDONE on the actual receiver TOGGLES, lowercase/no-octave (2026-09-29, on `main`,
  `da5f3b8`; iOS builds; DEVICE eye owed). Paul: "I actually intended this for the toggles, not the receivers
  themselves. Also, make them lowercase without the octave number." The entry above landed on
  `buildReceiverControl`'s big 4-button strip (the ENABLE/LATCH/OCT/S-M column) — fully reverted (`recLiveLabel`
  deleted, `recChanLabel` + its call site restored byte-for-byte). "The receiver toggles" are a DIFFERENT, smaller
  control: `buildReceiverSelectChip` (via the shared `buildIOSelectChip`), the per-row A/B/C/D door-picker chips
  under the machine box — these ALREADY had a "show the key instead of the letter" mechanism for a SCALE/CHORD door
  (`key`, via `receivers[i].scaleLabel`/`buildChordDoorLabel`, a top/big label swap so the letter survives as a small
  caption) — exactly the "leave one set to key" case, so that branch is UNTOUCHED. Added a new `live` branch using
  the SAME top/big swap: when a door has no key AND currently has held notes (`liveNoteClassLabel`, a new pitch-
  CLASS-only reader of the same `recvHeldNotes` feed — no octave digit, lowercased, e.g. "c e g", per Paul's literal
  ask), the big slot shows that instead of the plain letter; idle (nothing held, no key) still falls back to the
  plain A/B/C/D letter exactly as before — a chip is never left blank. Two held notes an octave apart collapse to the
  same letter twice (e.g. "c c") — an honest, undeduplicated consequence of dropping the octave, flagged not fixed
  (Paul didn't ask for dedup). MIDI-OUT emitter toggles (`buildEmitterToggles`, the sibling caller of the same shared
  chip) are UNTOUCHED — Paul named receiver toggles specifically. **DEVICE-OWED:** legibility of several lowercase
  letters in the chip's compact space, and whether a CHORD-mode door (still covered by the pre-existing `key` branch,
  unaffected by this pass) reads right alongside the new live-notes chips.**
  **"NO INPUT" ADDENDUM, same day (`a75ec6a`; iOS builds; DEVICE eye owed).** Paul: "this works well on the first
  receiver toggle. I also expect to see the notes or 'no input' appear on the other emitter toggles (the exception
  being scale)" — clarified via AskUserQuestion (2 corrections already landed on this exact feature this session, so
  asked rather than guessed a third time): he meant the other 3 RECEIVER chips (B/C/D), not the separate MIDI-OUT
  emitter toggles — "no input" is receiver-side language, which was the tell. ROOT ISSUE: the idle fallback was the
  PLAIN LETTER (byte-identical to the chip's own resting state), so a receiver with nothing currently held looked
  indistinguishable from "this feature doesn't apply here" — not a bug in the logic (every chip already ran the same
  code), just an invisible result. FIX: idle now shows literal `"no input"` (lowercase, matching the note-name
  convention) instead of falling back to the letter. Simplified the top/big swap while in there: since EVERY branch
  now fills the big slot with something (key · live notes · "no input"), the top caption is unconditionally the
  letter — the old `"MIDI IN"` fallback caption is dead code (no remaining case reaches it), removed. Scale/chord
  doors are UNCHANGED (still their own `key` branch, exactly the "exception being scale" Paul named).**
  **CHORD-DOOR FIX, same day (`eeafcda`; iOS builds; DEVICE eye owed). Paul: "it doesn't work on chord receiver
  toggles - it still shows 'chord'."** Self-inflicted: the `key` exception (the entry above's own "Scale/chord doors
  are UNCHANGED" line) wrongly carried CHORD doors along with SCALE ones — the ORIGINAL pre-existing code bundled
  `receivers[i].scaleLabel` and `buildChordDoorLabel` under one `key` value (both being "this door has a special
  identity" cases), and this feature's first pass never questioned that bundling. But Paul's own words, both times
  ("leave one set to key," "the exception being scale"), only ever named scale/key — never chord. A CHORD door was
  showing `buildChordDoorLabel`'s fixed `"A · CHRD"` string, which reads as "it still shows 'chord'." FIX: dropped
  `buildChordDoorLabel` from `buildReceiverSelectChip`'s `key` entirely (it's still used elsewhere — the tab-label
  call site at line ~211 — only THIS chip's use of it is gone) — a CHORD door now falls through to the same live-
  notes/"no input" branch as any plain input door. Its `recvHeldNotes` entry is that door's own resolved chord pool,
  live — a meaningful "what's sounding from here right now" readout, not a stand-in.**
- **▶ EUCLID MASK CHORD "not sounding" — INVESTIGATED, NOT REPRODUCIBLE off-device; +2 permanent regression tests
  (2026-09-29, on `main`, `10863ef`; macOS 1149 green incl. 2 new). Paul: a Euclid mask after an arp, GAPS=CHORD,
  7-of-8, wasn't sounding, "fails on every setting" — then gave the exact steps: the chain was ARP→VELOCITY, he added
  EUCLID MASK after it (still silent on CHORD), removed VELOCITY (still silent). Exhaustive engine-level
  investigation could NOT reproduce this: the CHORD stab mechanism (`chainScratch`/`composeChainSet`), `isModifierFoldable`/
  `chainDriverIndex`'s fold selection, `emitDriverNote`'s mask block, K/N/GAPS/ROTATE/CHORD PICK/SPAN/FILL/ACCENT LAYER
  param resolution, every `emitOneBus` suppression gate (mute/octave-clamp/RACK FENCE/CLAIM/solo/flood-governor/MONO,
  all confirmed off by default), and `openVoice` all check out clean by direct reading; Paul's TWO literal repro shapes
  were built and tested directly — `[ARP→EMPTY/bypassed→EUCLID MASK]` (the real post-removal shape; chain edits are
  POSITION-PRESERVING, `buildChainRemoveSlot` leaves a bypassed `.empty` passthrough and never shifts later slots) and
  `[ARP→VELOCITY→EUCLID MASK]` (his original, pre-removal chain) — both strike the chord correctly. The storefront
  "ADD PROCESSOR" card for EUCLID MASK applies no param preset (`apply: { _ in }`), so a freshly-added slot is
  identical to direct construction. **A real dead-code finding along the way, flagged not fixed:** `Router.
  auditionRender` — a separate, simpler render path for a press-and-hold single-cell preview — only ever previews a
  chain's HEAD slot (its own comment says so: "a full serial preview of the tail is a follow-up") and would have
  PERFECTLY explained this exact symptom (a downstream processor silently ignored) if it were reachable. It isn't:
  its sole trigger `MidiSparkAudioUnit.setAudition(col:row:)` and the `AuditionBox.target`/`.held` state it depends on
  are never written anywhere in the current codebase (grepped clean) — today's real preview mechanism instead parks
  the audition machine as a genuine playing cell (`BuildSceneLogic.composeSceneMeta`'s `auditionRow`) and renders it
  through the same full engine as any other cell, so this dead path isn't actually reachable from the UI. **Also
  flagged (minor, not what Paul described but a real discoverability trap):** a freshly-added EUCLID MASK defaults to
  K=N (fully open/pass-through — `mK = p.maskK ?? mN`), and the GAPS/ROTATE/CHORD PICK/CHORD OCT/LEN/VEL rows are all
  HIDDEN until K is manually lowered below N, so there's nothing to tap toward "chord mode" on a brand-new slot until
  HITS is touched first. +2 RouterTests locking in Paul's two repro shapes as permanent coverage
  (`testEuclidMaskChordFoldsAcrossAPositionPreservingEmptySlot`, `testEuclidMaskChordFoldsWithVelocityStillInTheChain`).
  **GENUINELY UNRESOLVED — asked Paul for the detail needed to keep chasing it:** whether he's checking via the
  press-and-hold/tap audition or by actually pressing PLAY on a scene; his CHORD PICK setting (ALL vs. a narrower
  pick could read as "nothing" if it's e.g. LOW/HIGH and he's listening for the whole chord); whether EUCLID MASK is
  the chain's last slot or anything follows it; any other processor anywhere else in the chain.**
  **BOTH FLAGGED ISSUES FIXED (2026-09-29, on `main`, `33d2266`; iOS builds). Paul confirmed he's not auditioning
  (real playback), it fails on every CHORD PICK mode, and EUCLID MASK is the chain's last slot, then asked me to fix
  the two issues found above. (1) `Router.auditionRender` and its whole "Phase 2" dead-preview cluster REMOVED at
  every entry point: `AudioUnitViewController.swift`'s `AuditionBox` class + `abox` @State (its `target`/`held`
  fields were written only to their own already-default values, never read anywhere); `MidiSparkAudioUnit.
  setAudition(col:row:)`/`clearAudition()`; and — found while removing these, same dead "Phase 2" era, same
  shape (zero UI callers) — `MidiSparkAudioUnit.setPreview`/`clearPreview` too. Deliberately did NOT chase the
  removal all the way down into `Kernel.swift`'s `auditionTarget`/`previewActive`/`suppressAuditionNotes` fields
  or `Router.process()`'s `audition:`/`preview:` parameters — those are live plumbing read by the render loop's
  own gates on every render (`auditionSuppressing: suppressAuditionNotes || previewActive || …`), and safely
  unwinding a load-bearing function signature deserves its own focused pass, not a rushed side-fix; they're now
  commented as permanently-dead-but-still-read, and Kernel.swift's own two setter methods that only these deleted
  callers used (`setAudition`/`setPreview`/`clearPreview`) are gone too since nothing calls them anymore. Net
  effect: this render path can no longer be reconnected from the UI by accident — it would need genuinely new code.
  (2) The K=N discoverability trap in the EUCLID MASK editor (GridUI.swift) — GAPS/ROTATE/PATTERN/CHANCE/the CHORD
  sub-fields are no longer hidden behind `if mK < mN`; they're always visible now, with a plain one-line hint
  ("K = N — every step hits, so GAPS/ROTATE/CHORD have nothing to act on yet") shown only when the mask is
  currently fully open. **A THIRD possibility raised, not yet code — a listening-window hypothesis, not a bug:**
  reconciling "7-of-8 fails, and so does every OTHER setting he tried" — K=7/N=8 leaves exactly ONE gap per 8-note
  cycle; if GAPS/CHORD PICK are being toggled and listened to for only a second or two each (very natural while
  dialling in a setting), the one gap-per-cycle may simply never be reached before moving on — which would equally
  explain "fails on every CHORD PICK mode" (the pick differentiator never gets a chance to be heard if the gap
  itself is never reached). Asked Paul to test a much denser mask (e.g. 4-of-8) over 2+ full cycles, and separately
  whether REST/TIE modes have ANY audible effect at all (drops/ties a note) with his current settings — the single
  most decisive remaining diagnostic: if REST/TIE do nothing either, the whole downstream fold isn't engaging (a
  bigger, different, and more findable bug than the CHORD stab specifically); if REST/TIE clearly work and only
  CHORD's replacement note is silent, that narrows the search to the stab's own emission call.**
- **▶ FERRY DRAG-DROP — silent ferry + un-stopped source audition FIXED, the source cell now commits (name+colour),
  +2 tests (2026-09-29, on `main`, `aada129`; macOS green incl. 2 new, iOS builds; DEVICE ear/eye owed). Paul reported
  three bugs dragging a SELECT cell onto a play ferry: the source cell kept playing, the target ferry stayed silent,
  the source cell never got marked/named. **ROOT CAUSE of the silent ferry — A REGRESSION FROM THIS SAME DAY'S
  EARLIER FIX** (the `1c902c6`-adjacent "only navigate to PART if already focused" change): `buildPublishScene`'s
  `input.ferryParts[t] = t == buildActiveFerry ? buildCaptureBenchPart() : buildFerryParts[t]` — an ACTIVE ferry is
  read LIVE off the editing "bench" @State, every OTHER ferry from its own stored `BuildPart`. The earlier fix set
  `buildActiveFerry = t` on a non-focused drop WITHOUT loading `t`'s data onto the bench — so the compositor kept
  reading whatever the PREVIOUSLY active ferry had left there, not the drop. Same shortcut skipped the chain-
  audition-stop (it only ran on the navigate-to-PART branch) — the un-stopped source cell was the SAME root cause,
  not a separate bug. **FIX:** `buildActivateFerry`/`buildReactivateFerry` gained a `navigate: Bool = true` param —
  the FULL activate flow (outgoing-ferry bench writeback, bench LOAD of the new ferry, the chain-audition stop) now
  ALWAYS runs; `navigate` gates ONLY the room switch + `roomsPartSetup()`. `buildPopulateFerry` calls through this
  properly instead of the hand-rolled `buildActiveFerry = t; buildPublishScene()` shortcut the earlier fix used.
  Traced the fix by hand against the exact `buildPublishScene` composition code before shipping (not assumed) —
  confirmed a non-focused drop now correctly bench-loads `t`, publishes with `t`'s real content, and separately
  writes back the OUTGOING ferry's live edits so IT keeps sounding right too. **SOURCE-CELL COMMIT:**
  `buildPopulateFerryFromSelect` now marks/names the SOURCE cell, mirroring the existing "EDIT = COMMIT" rule an
  in-place chain edit already applies (`buildApplyChain` — first name wins, the colour override always follows) —
  this never ran for drag-drop at all before, which is exactly why it "did this in some instances already" (only
  when a PRIOR edit had happened to commit the cell first). **TESTS:** extracted the two genuinely pure rules —
  which name wins (`BuildSceneLogic.ferryDropSourceName`) and whether to navigate
  (`ferryDropShouldNavigateToPart`) — into `BuildSceneLogic.swift`, `BuildPage.swift` now calls THROUGH them rather
  than duplicating the logic inline, +2 `BuildSceneLogicTests`. **HONESTLY FLAGGED, not swept under a test:** the
  actual bench/active-ferry sync bug lives entirely in SwiftUI `@State` glue (`buildLoadBenchPart`/
  `buildCaptureBenchPart` read/write ~20 `@State var`s directly) — this project's own architecture deliberately
  keeps that class of code OUT of the unit-test target (BuildPage.swift isn't in `MidiSparkTests`); traced it by
  hand instead of forcing an artificial pure-function extraction that wouldn't actually cover the real bug. **DEVICE-
  OWED:** drop onto a non-focused ferry → it should audibly start playing the dropped content immediately, the
  previously-focused ferry should keep sounding unaffected, the source SELECT cell should go quiet + show its name,
  and switching to PART later should show the newly-active ferry's part (not stale bench content).**
- **▶ PART GRID — a live per-row piano roll of what actually played, overlaid on the existing grid (2026-09-29, on
  `main`, `56868a9`; macOS 1145 green incl. 4 new, iOS builds; DEVICE eye/ear owed). Paul: each of the part grid's 4
  interior rows should show a LIVE piano roll of the notes it actually played — pitch vertically, time horizontally,
  riding the row's own existing sweeping playhead — accurate, no perceptible latency, fading at a FIXED trailing
  window behind the playhead (a rolling lookback from NOW, not from a held note's onset — its head stays bright at
  the playhead as long as it's held, its tail fades at a fixed distance regardless of hold length). Planned carefully
  first (10 ACs ratified in chat, then a formal EnterPlanMode pass with 2 parallel Explore agents + 1 Plan agent,
  self-reviewed against the ACs before implementing — 3 real gaps caught and fixed pre-code: velocity wasn't wired to
  any visual, an early draft cleared the roll on transport-stop which directly violated the no-abrupt-reset AC, and
  the ~33ms poll-bound "how fast can a note appear" honesty wasn't stated plainly). **SCOPE, confirmed via
  AskUserQuestion:** one roll PER ROW (not one combined roll for the whole part); it lives ON the existing grid as an
  overlay (not a new strip/page element — no layout/lattice change at all); a bar stays FIXED at its own grid column
  and fades in place (opacity only), a held note's head still extends forward with the live playhead. **ROOT DESIGN
  PROBLEM: the render engine had no per-voice onset TIME at all** — `Router.Voice` tracked active/note/vel/cellIndex/
  offSample but nothing about WHEN a voice opened. Fixed by adding `Voice.onBeat: Double`, stamped inside `openVoice`
  using the IDENTICAL formula the existing `focusNoteBeat` comet-trail already uses (`fBeatPos + Double(onSample −
  fWindowStart) × fBeatsPerSample`) — these are Router INSTANCE fields set once per render window, so no signature
  change was needed on `openVoice` or any of its 13 call sites. New `Router.rowSoundingVoices()` bucket-scans the
  128-voice pool ONCE by engine row (`cellIndex % Snap.rows`), returning every row's (note,vel,onBeat) — mirrors
  `cellSoundingVelSnapshot`'s existing "return the whole unscoped array" shape rather than threading a ferry/row
  param through 3 forwarding layers. Threaded through Kernel/MidiSparkAudioUnit as thin forwarders, polled on the
  **30fps `meterTimer`** (the OUT-piano's just-landed precedent from the day before — NOT the laggier 4Hz diagnostic
  timer), reconciled into a new `LiveTelemetry.partRollNotes` (plain reference-class field, not `@State`, matching
  `cellRoll`'s existing pattern so per-note writes don't force a body re-run). **THE SUBTLE BUG THE PLAN AGENT CAUGHT
  BEFORE ANY CODE WAS WRITTEN:** `onBeat` is captured RAW (un-swing-warped, matching `focusNoteBeat`), but the
  existing playhead (`roomsPartPlayhead`) runs its beat through `musicalOf` (the swing warp) before it becomes a
  pixel — comparing a raw note-beat against a musical playhead-beat directly would have silently drifted the bars off
  the white sweep line under any non-50 swing setting. Fixed by applying `musicalOf` to BOTH the live beat and every
  note's beat at draw time, never comparing raw-to-musical. **LOOP-COLUMN SELECTION EDGE CASE, also caught in
  planning:** a loop-column selection can map adjacent logical steps to non-adjacent physical columns
  (`BuildSceneLogic.loopColumnPlan`) — a naive single-rectangle bar would smear across skipped columns, so a held
  note's bar is decomposed into one segment per LOGICAL step, each positioned via the SAME `plan.physicalColumn`
  the playhead itself uses — this also gives the loop-seam CLIP (never wrap) for free, matching the fade
  clarification Paul gave. **KNOWN, STATED LIMITATION (not a bug):** detection depends on the ~30fps poll observing
  "what's active right now" — a note shorter than ~33ms, or repeated strikes closer together than that (a fast
  ratchet/burst can exceed it), can open and fully close BETWEEN two polls and never be observed at all, not merely
  delayed. No faster live-voice channel exists in this codebase today; flagged explicitly in the plan and here rather
  than discovered as a surprise later — device-verify against a real fast ratchet before calling this fully done.
  Also explicitly NOT clearing `partRollNotes` on the transport-stop edge (an early draft did — removed: it fought
  the no-abrupt-reset AC and was pure downside, since the overlay is already gate-hidden while stopped via the same
  `d.effectivePlaying` gate `roomsPartPlayhead` uses). Reused verbatim, not reinvented: `rollLaneForPitch`
  (pitch→lane, already used by the dead-but-still-populated `meters.cellRoll`/`buildNoteSweep` pathway) and
  `partFerryHue(row:)` (the exact colour already tinting the flat part cells this overlay sits on top of).
  **DELIBERATE, SCOPED EXCEPTION to "GRID REBUILD P2" (2026-09-08, "cells are calm, the ferry row carries the
  motion")** — the roll is a new overlay layer riding above the flat, unchanged part cells, not a reversion of that
  redesign; worth device-confirming it doesn't read as visually contradicting the calm-grid intent elsewhere. +4
  RouterTests (onset-beat accuracy on a SUSTAINED hold — an ARP's staccato notes were the first draft's mistake, all
  already gated off by the check point, caught by the test failing, not by inspection; row-bucketing across a real
  ferry boundary, row 0 vs. row 4; clears on release; the existing silent-claim-ghost exclusion pattern extended to
  the new method). One test-writing lesson recorded plainly: the first draft of the onset-beat test also asserted 3
  voices for a 3-note chord and failed at 6 — §7b's own two-cable-per-note copy (own bus + the ALL cable) means
  `rowSoundingVoices()`, a deliberately raw per-voice dump, legitimately reports 2 voices per logical note; the UI
  layer's `(pitch,onBeat)` dedup (not Router) is what collapses that back to one bar. **DEVICE-OWED:** the whole
  feature — no-perceptible-lag on strike, a held note's tail pinned at the 2-beat window while its head tracks the
  sweep, non-zero swing not drifting the bars off the white line, a loop-column selection not smearing a bar across
  skipped columns, velocity actually reading as thinner/dimmer for soft notes, and the fast-ratchet miss-limitation
  either not noticeable or worth a follow-up if it is. Plan: `~/.claude/plans/velvet-foraging-curry.md`.**
- **▶ FERRY DRAG-DROP — a SELECT-cell drop no longer force-navigates to the part grid unless the target ferry was
  already focused (2026-09-29, on `main`, `59f6bdb`; iOS builds; DEVICE eye owed). Paul: dropping a SELECT cell onto
  a play ferry shouldn't yank the view over to the part grid unless that ferry's own selector was already the active
  one — otherwise stay on whatever room you're in, but still let "the selected colour" (`buildActiveFerry`) follow
  the drop. ROOT CAUSE: `buildPopulateFerry`'s trailing `buildReactivateFerry(t)` was unconditional — it always
  called through to `buildActivateFerry(t)`, which (since the ferry is now populated) always takes the "load bench +
  `roomsRoom = .part`" branch, regardless of whether `t` was the ferry you were already looking at. **FIX:** capture
  `buildActiveFerry == t` right before that trailing call (nothing above it in the function touches `buildActiveFerry`,
  so it still reflects the PRE-drop focus) — already-focused → unchanged behaviour (`buildReactivateFerry`, full
  bench load + navigate); a DIFFERENT, non-focused ferry → populate + colour-swap runs exactly as before (untouched),
  the ferry starts playing in the BACKGROUND (consistent with the ferry-row-unification model, where every ON ferry
  already composes/plays independently of which one has focus), and only `buildActiveFerry = t` updates (+
  `buildPublishScene()` so the newly-armed play state actually takes effect) — no bench load, no room switch. Scoped
  to exactly the SELECT-cell→ferry drop path (`buildPopulateFerry`, the only caller of the old unconditional call);
  ferry→ferry drag-moves (`buildMoveFerry`) are untouched — Paul's ask named the SELECT-cell case specifically.
  UI-only, no test-target reach (GridUI/BuildPage, as always). **DEVICE-OWED:** dropping onto a non-focused ferry
  reads as "it populated and started playing, right where I was" rather than as a dead tap; the SELECT cell's border/
  play badge (the two things this session already wired to "the selected colour") pick up the new colour immediately.**
- **▶ RANDOMIZE/MUTATE — a REAL progress bar on both the machine panel and the part grid (2026-09-29, on `main`,
  `b7591af`; macOS green (full suite), iOS builds; DEVICE eye owed). Paul: show a progress bar while RANDOMIZE/MUTATE
  is in process, from either surface. **MACHINE PANEL:** already backgrounded since the 2026-09-13 tranche
  (`runOnLargeStack` + `buildMachineGenerating`), just showed an indeterminate circular `ProgressView()` — swapped for
  `ProgressView(value: buildMachineGenProgress)` (`.progressViewStyle(.linear)`). **PART GRID:** the row-creator's
  MUTATE/RANDOM/TRY-AGAIN (`roomsRowCreatorInline`/`buildRegenRow`) were STILL SYNCHRONOUS on the main thread — a
  gap explicitly flagged and left open in the 2026-09-13 tranche's own forward-plan ("Background the synchronous
  row-creator MUTATE/RANDOM"), never picked up until now. New shared `buildRowGenerate(row:random:base:)` — one
  guard (`buildRowGenRow`, keyed by row not a bare bool), one `runOnLargeStack` dispatch, one completion handler —
  replaces the three near-duplicate inline call sites; a new `roomsRowGeneratingInline` shows the bar in the SAME
  row footprint the creator/confirm buttons already use, wired into the part-grid's per-row switch (now a 4-way:
  generating → confirm → creator → cells) and into the drag-gesture guard (a generating row can't also take cell
  taps, matching the existing KEEP\|TRY-AGAIN row's own guard). **THE BAR IS REAL, NOT SIMULATED** — checked this
  before building anything: `Dice.fingerprint`/`evalRun` (which both `mutateChain`'s retry loop and `rollSimple`'s
  candidate loop call every iteration) run a genuine offline Router probe (`runRecorder`, 3 beats each) — a real,
  not-fake cost per attempt, confirmed by reading `runRecorder` directly rather than assumed from the loop shape
  alone. So `attempt/24` (mutateChain's hard cap) and `candidate/4` (rollSimple's) are honest proxies for work
  actually done, not a decorative timer. Threaded an optional `progress: ((Double) -> Void)? = nil` through BOTH
  pure functions (BuildSceneLogic.swift, Dice.swift — both Foundation-only, no UI dependency added; the callback
  itself hops to main via the caller, same pattern as the existing completion handler) — additive, every existing
  caller/test unaffected (confirmed, not assumed: ran the full macOS suite). **A real bug caught before it shipped,
  not after:** a first draft used `defer { progress?(...) }` per loop iteration for the "didn't finish yet" case —
  but the fast-path early return (`if !scored { progress?(1); return chain }`) would have fired its OWN 100% call
  and THEN the deferred per-attempt fraction on the way out (defer always runs on scope exit, including via
  return), landing the bar back below 100% instead of at it. Caught by tracing the actual control-flow order before
  shipping, not by a test (no test-target reach for this — see below) — rewritten with explicit calls at each exit
  point instead of `defer`, so every path reports its OWN final value exactly once. RANDOMIZE's rare cold-corpus
  fallback (`Dice.rollArchetype`, only reachable when the pregen corpus isn't warm yet) has no natural sub-steps to
  report — left as a small 0.08 head-start snapping to 1.0 on completion, honest about not knowing more than that,
  not worth over-engineering for a path that's usually instant anyway. UI-only for the wiring; the two engine
  signature changes have no test-target reach for the NEW behavior specifically (the callback itself isn't asserted
  by a test, only that existing callers/tests still pass unmodified) — DEVICE-OWED: the bar's legibility at both
  panel and row-creator size, and that rapid-fire RANDOMIZE/MUTATE taps (either surface) can't desync the guard from
  the visible state.**
- **▶ PROCESSOR EDITOR — the swap transition is now SLIDE + FADE, not a plain cross-fade (2026-09-29, on `main`,
  `7ad1775`; iOS builds; DEVICE eye owed). Follow-through on the 2026-09-28 cross-fade fix: Paul asked whether it'd
  landed (he couldn't see it), then for suggestions on feel — shown as an interactive mockup comparing candidates
  (opacity-only · slide+fade · scale+fade · flash · flash+slide) built from the shipped code's own actual gaps, not
  invented; he picked slide+fade. **THE TRANSITION:** `ProcessorBox`'s new `swapTransition` (GridUI.swift) — a small
  FIXED 14pt offset + opacity, `.asymmetric(insertion:removal:)`, NOT SwiftUI's built-in `.move(edge:)` (which travels
  the view's own full width — far too big a sweep at panel size for a subtle cue, caught before shipping by reasoning
  through what `.move` actually measures against, not assumed). Direction is `swapDirection: Int` (new `ProcessorBox`
  param, default +1): the incoming controls nudge in from the edge matching which way the user actually moved through
  the chain; the outgoing controls nudge out the opposite way. Duration bumped 0.18s→0.2s to match what read best in
  the mockup comparison (a touch more time for the added motion). **DIRECTION SOURCE:** `buildEditSlot` (0…7) already
  IS the chain's own left-to-right order — no new positional concept needed. A new `buildEditSlotDir` @State
  (AudioUnitViewController.swift) derives it via `.onChange(of: buildEditSlot)` (comparing against a remembered
  `buildEditSlotLast`), threaded into the ONE call site tied to the real chain editor (`buildSlotBox`'s own
  `ProcessorBox(...)` call, BuildPage.swift). Both surfaces Paul originally named — the MIDI-chain box grid
  (`buildProcBox`) and the tab strip above the panel (`buildProcCardTabs`/`buildProcTab`) — already write the SAME
  `buildEditSlot`, so both get the directional treatment for free, no separate wiring per surface. The OTHER
  `ProcessorBox` call site (the chord-sequencer popup, `buildChordSeqEditor` — a 4-slot radio with no real chain
  position) keeps the `swapDirection` default (+1) — still gets slide+fade, just not adaptively directional; not a
  regression (it had no transition beyond the shared cross-fade before either). **UNCHANGED, flagged again for
  clarity:** still fires ONLY on an actual TYPE change (the existing `.id(ft)` mechanism) — switching between two
  same-typed slots (e.g. two ARPs with different params) still shows nothing; that's the separately-flagged gap from
  the mockup's own "same-type switches" toggle, not addressed by this pass. UI-only, no test-target reach (GridUI, as
  always). **DEVICE-OWED:** the 14pt/0.2s feel at real panel size and normal tap cadence, and that rapid back-to-back
  swaps (slot→slot→slot) don't visually overlap or stutter.**
- **▶ FERRY DRAG-AND-DROP — a DEALT cell's transpose now bakes into the chain, not a machine field (2026-09-28/29, on
  `main`, `9272248`; iOS builds; DEVICE-ear owed). Paul asked me to investigate circumstances where dragging a SELECT-
  grid cell onto a play ferry changes its output. Traced the whole path (`buildFerryDrop` → `buildPopulateFerry-
  FromSelect` → `buildPopulateFerry` → `buildNewTabMachine`) against what the SELECT-grid audition actually plays
  (`buildGridSelLoadChain`, `composeSceneMeta`). **ROOT CAUSE:** a DEALT (tab 0, "RE-DEAL" bank) cell carries a per-
  archetype REGISTER transpose (`Dice.transposeFor`: bass −12, arp/sparkle +12, pad/wild ±12 — a full octave, not a
  rare amount). The SELECT-grid audition bakes this as a LEADING `.transpose` UTILITY PROCESSOR inserted at chain
  position 0 (`buildGridSelLoadChain`) — so it shifts the notes BEFORE the rest of the chain runs. `buildPopulateFerry`
  instead handed the same number to `buildNewTabMachine` as a MACHINE-LEVEL `transpose` field, which `Router.
  machineTranspose` applies AFTER the whole chain has already composed (added directly to the chain's already-composed
  OUTPUT — confirmed e.g. at the ECHO-tail sites, Router.swift ~2071/2100). Pre-chain vs. post-chain transpose is only
  mathematically identical for a chain that's pitch-shift-transparent throughout; it diverges the moment any stage's
  result depends on ABSOLUTE register rather than a relative offset (chiefly the hard 0–127 clamp, "out-of-range notes
  drop" — Router.swift:4366 — or a chain that layers its own further octave movement on top of the archetype's own
  ±12) — so the exact notes that come out could differ between what was previewed and what plays from the ferry, same
  chain, same transpose number. **SCOPE:** only an UNEDITED bank-0 DEALT cell — the moment any processor-card param is
  touched, `buildApplyChain`'s existing "EDIT = COMMIT" path (2026-09-12) bakes the chain into `buildGridSelOverride`
  WITH the transpose already inserted as a real chain slot, so both paths agree from then on. MY LIBRARY cells (tab 1)
  and cell-to-cell copies always carry transpose 0 (`buildGridSelChainAt`), so they were never affected. **TWO
  THEORIES CHECKED AND RULED OUT** (traced, not assumed): a receiver/emitter "sticky" mismatch — doesn't exist, both
  paths read `buildSelReceiver`/`buildDefaultEmitters` live and `buildPublishScene` re-resolves the audition's door on
  every edit; a stale/un-committed live edit — already covered by the 2026-09-12 EDIT = COMMIT fix. **FIX:**
  `buildPopulateFerry` now bakes `transpose` into `chain` the SAME way `buildGridSelLoadChain` does (a leading
  `ProcessorSlot(type: .transpose)`, clamped ±24, inserted at index 0) before calling `buildNewTabMachine` with no
  machine-level transpose — so the dropped ferry's chain sees exactly what the SELECT-grid preview's chain saw.
  `buildNewTabMachine`'s `transpose:` param/machine-level path is untouched (its only other caller already passes the
  default 0). UI-glue code (BuildPage.swift, not in the macOS test target) — no new unit test, matching every prior
  GridUI-only fix in this file. **DEVICE-OWED:** a BASS/ARP/SPARKLE/PAD/WILD DEALT cell with a register-sensitive chain
  (near the keyboard extremes, or with its own octave-shifting stage) actually sounding identical before/after the
  drop now.**
- **▶ ROOMS WORKBENCH — the machine column moved LEFT of the grid; its trash/verb-button flanks swapped (2026-09-28,
  on `main`, `1c902c6`; iOS builds; DEVICE-eye owed). Paul: move the whole right column (receiver toggles · machine ·
  emitter toggles) to the left instead of the right, and swap the LIBRARY/MUTATE/RANDOMIZE/CLEAR verb-button stack
  with the trash/row-rail flank around it. **PAGE LAYOUT:** `RoomsPage.roomsWorkbench`'s HStack order flipped —
  `chainPanel` (the receiver strip · machine box · emitter strip) now renders FIRST (1/3, LEFT), the active grid
  (SELECT or PART, 2/3) now RIGHT — was grid-left/chain-right since the 2026-09-08 workbench merge. **MACHINE-BOX
  FLANKS:** inside `roomsMachineStrip` (BuildPage.swift), the two flanks either side of the MIDI-chain block swapped
  — `buildChainButtonStack` (LIBRARY/MUTATE/RANDOMIZE/CLEAR) now LEFT, the `ZStack{roomsMachineRowRail (PART only) ·
  roomsChainTrash}` now RIGHT — in both the populated-chain branch and the faded empty-part-row placeholder branch, so
  the two stay visually consistent. **HIT-TEST FOLLOWED THE MOVE:** `buildProcBox`'s drag-to-delete gesture detected
  "over the trash" via `drag.location.x < -6` in the chain block's own "chainBlock" coordinate space (the trash sat at
  negative x, the LEFT flank) — now `drag.location.x > blockW + 6` (positive x past the block's own right edge,
  `blockW = w·2 + gap` computed locally from the per-box width already in scope), matching the trash's new RIGHT-flank
  position. The ferry-drag trash hit-test needed no change — `roomsChainTrash` registers its drop zone via real
  on-screen geometry (`FerryZoneKey`/`.named("rooms")`), so it tracks wherever the view actually renders. The chain's
  own IN/OUT velocity-meter overlay (`buildChainFlowOverlay`, left circle = input door, right circle = emitted output)
  is untouched — it reads MIDI flow direction through the chain, independent of which flank the buttons/trash occupy.
  **NOT TOUCHED:** the PART grid's own internal row-select rails (chevron rail left / numbered rail right, inside
  `roomsPartGrid` itself) — a separate, unrequested feature; only the machine-box's own flanks and the page-level
  grid↔machine order moved. **DEVICE-OWED:** the whole re-arranged layout on a real screen, and that dragging a chain
  box to the NOW-right-side trash still deletes it (the hit-test math is unit-untestable — GridUI has no test-target
  reach, same as every prior playhead/layout fix in this file).**
- **▶ ROOMS WORKBENCH — the left/right layout swap REVERTED (2026-09-29, on `main`, `28641fb`; iOS builds). Paul: back
  to the original layout. A clean `git revert` of `1c902c6` (same-day, "move the machine column to the left, swap its
  trash/verb-button flanks") — applied with no conflicts against this session's other BuildPage.swift edits (all in
  unrelated regions). Restores: `roomsWorkbench`'s top-level HStack back to GRID (2/3, LEFT) · MACHINE BOX (1/3,
  RIGHT); within the machine box, TRASH/row-rail flank LEFT · verb buttons (LIBRARY/MUTATE/CLEAR) flank RIGHT, for
  both the populated and the faded-empty-row layouts; the chain-box drag-to-delete hit-test back to `drag.location.x
  < -6` (was `> blockW + 6`). Net: `1c902c6` is now fully undone, nothing else changed.**
- **▶ PLAY FERRIES — M/S collapsed to a single SOLO button (2026-09-29, on `main`; iOS builds; DEVICE eye owed). Paul:
  replace the mute+solo pair under each play ferry with one "SOLO" button, same size. `roomsPlayFerry`'s `HStack { M;
  S }` (each half-width) is now one full-width `Text("SOLO")` calling `buildToggleFerrySolo(t)` — same amber-when-
  soloed styling the S button had, same overall footprint/height (`selH`, matching the selector row above it) the
  M+S pair used to fill together. **MUTE'S UI IS GONE, its plumbing ISN'T:** `buildToggleFerryMute`/
  `buildPlayColMute`/`buildFerryAudible`'s mute check, and the ferry-move carry-over that copies a source ferry's
  mute state onto its target, are all UNTOUCHED — a ferry can still end up muted (an old saved doc, a future code
  path) and `buildFerryAudible`/the silenced-dimming visual will still honor it correctly; there's just no button
  left to SET it. Scoped to exactly what was asked (a UI button, not a feature removal) — flagged in case Paul
  actually meant to drop mute everywhere, not just its ferry-row control.**
- **▶ EMITTER TOGGLES — zero emitters is now selectable, chase-pulses an invite when reached (2026-09-29, on `main`;
  iOS builds; DEVICE eye owed). Paul: let the MIDI-OUT A–D toggles go to nothing selected, and when they do, animate
  all four "in order" to invite a pick. **REACHING ZERO:** `buildToggleBus`/`buildToggleBusAll` (BuildPage.swift)
  each had a `if buses.isEmpty { buses = [bus] }` guard — "never leave a row with no output" — removed from both, so
  toggling off the last emitter now actually lands on an empty set instead of snapping back on. That alone wasn't
  enough: TWO resolvers upstream of the toggle also forced non-empty — `buildRowEmittersResolved` treated an
  explicitly-empty per-row override the SAME as no override at all (`if let own, !own.isEmpty { return own }; return
  buildDefaultEmitters` — an empty `own` fell through to the default) and `buildDefaultEmitters` itself collapsed
  `buildPartEmitters.isEmpty` to `[.a]`. Both changed to respect an explicit empty set as a real value — nil (never
  touched) is still the only thing that falls through to a default now. Safe precedent already existed: the
  fresh-cell `buildIONullPending` state already runs the engine at busMask 0 on purpose ("the fresh cell is SILENT
  until wired") — zero real emitters was already a proven-safe engine state, just not reachable through ordinary
  toggling before this. Checked every reader of both resolvers first (all either `.contains()` or pass the Set
  straight into `chainEmitters`/`p.emitters` — no force-unwraps assuming non-empty). **THE INVITE:** a NEW
  `emitterChaseLevel(date:index:count:)` — a cosine bump per toggle index, phase-offset by its position (0…3) over a
  ~1.2s lap, cubed to sharpen the peak so ONE toggle reads "lit" at a time as the brightness sweeps A→B→C→D — drives
  a new `chaseIndex: Int?` param on `buildIOSelectChip`, wired only from `buildEmitterToggles` when the resolved set
  is empty AND it isn't the separate (already-static) `buildIONullPending` invite. Deliberately a DIFFERENT, animated
  treatment from that existing static cyan keyline (Paul 2026-09-08 flattened THAT one from a breathe to a steady
  mark) — this is a distinct state (a normal, previously-wired cell the user emptied out) with its own fresh, explicit
  ask for motion, not a reversion of that earlier call. The MIDI-IN receiver chip (the OTHER `buildIOSelectChip`
  caller) is unaffected — `chaseIndex` defaults to nil there.**
- **▶ SELECT GRID — the play badge left-aligned + vertically centred (2026-09-29, on `main`, `2276dcb`; iOS builds;
  DEVICE eye owed). Paul: match `roomsPlayFerry`'s own icon placement. `buildGridSelCell`'s play badge (added
  2026-09-28) moved from `.frame(alignment: .bottomTrailing)` + a same-order `.padding(4)` — which padded OUTSIDE an
  already-full-size frame rather than insetting the icon, a minor pre-existing mis-order — to `.padding(.leading, 4)`
  THEN `.frame(width: w, height: h, alignment: .leading)`: pads the icon first, then places the padded icon at
  `.leading` (horizontal-leading + vertical-CENTER, SwiftUI's `Alignment.leading`), mirroring the ferry button's own
  `HStack { icon; …; Spacer() }` inside a full-bleed `.overlay` (left-hugging content, vertically centred by the
  overlay since the HStack's natural height is shorter than the button).**
- **▶ PROCESSOR EDITOR — the OUT piano: latency cut to ~30fps + a stop/restart freeze fix (2026-09-29, on `main`,
  `cf14cdc`; iOS builds; NEITHER symptom is off-device reproducible — DEVICE-owed, best-effort root cause). Paul: "is
  there a way to get rid of the latency on the piano that represents a processor's output? Also, the piano animation
  stops working when I stop then restart the host transport." **LATENCY:** `buildOutHeld`/`buildRiffDrunkPos`
  (`AudioUnitViewController.swift`) were polled inside the 4 Hz diagnostic `.onReceive(timer)` — a real, quantifiable
  250ms worst-case lag behind the actual audio. Moved both to the existing ~30fps `.onReceive(meterTimer)` (the SAME
  timer the emitter/receiver peak meters already use for "low latency", per its own standing comment) — cuts the
  worst case to ~33ms. `cellSoundingNotes`/`riffDrunkPosAt` are plain live reads (a `voices[]` scan / array index, no
  draining queue — confirmed in Router.swift before relying on it), so polling them 8× more often is safe, no
  double-consumption risk. **THE FREEZE:** root-caused by reading, not an empirical device trace (neither symptom is
  reproducible off-device) — flagged as best-effort. `buildTruthStrips` (the IN/OUT piano view) computed its OWN
  "is MIDI reaching this instance" flag (`proc`) inside a `TimelineView(paused: animationsPaused || !dynamic)`, where
  `dynamic` required `buildDisplayVoice == .part && d.effectivePlaying && (…playing…)` — the ONE paused-gate in the
  whole file keyed on transport/effectivePlaying-derived state (every other `TimelineView` pause condition is either
  app-visibility (`animationsPaused` alone) or a plain `!d.playing`, not this specific compound). A TimelineView
  paused by transport state is a plausible spot to wedge across a stop→restart cycle, since its OWN schedule is
  exactly the mechanism that would need to notice the restart to resume ticking — and this mechanism was BRAND NEW
  (shipped alongside the OUT piano itself, `25dc00f`, earlier the same day), never exercised against a stop/restart
  cycle before now. **FIX:** `proc` is now `buildOutProcessing`, a plain `@State` computed in the SAME 30fps poll as
  `buildOutHeld` (`buildProcessing(at:)`, unconditional on `dynamic`) — `buildTruthStrips` reads it directly, no
  TimelineView of its own anymore. A plain `@State` write always forces a re-render (no schedule to get stuck);
  same 30fps refresh rate as before (no responsiveness regression) — and CHAIN-audition mode now gets the same fast
  treatment `dynamic`'s part-only gate never gave it. UI-only, no test-target reach (GridUI, as always).
  **DEVICE-OWED, both fronts:** the latency actually reads as fixed: and — the one I can't fully stand behind without
  a device trace — that a stop→restart cycle no longer freezes the piano. If it still does, the next place to look is
  `buildTransportEdge`'s `buildHostHalted` guard (`if buildHostHalted { …; buildPublishScene() }` on resume) — three
  OTHER call sites (`buildSetFerryPlay`, `buildTogglePlayGrid`, `buildRequestWorkshopVoice`) can clear
  `buildHostHalted` to false WHILE the transport is still stopped, which would skip the resume republish entirely if
  one of them fires between a stop and the next start; ruled less likely only because it should affect audible
  playback too (not just this display), which Paul didn't report — flagging in case the piano fix alone doesn't hold.**
- **▶ SELECT GRID — the picked-cell recolour reverted; the selected colour moved to a border + a play badge (2026-09-28,
  on `main`, `cbb3bb2`; iOS builds; DEVICE eye owed). Paul: revert the 2026-09-27 change where a picked-but-uncommitted
  SELECT cell's notes wore the active ferry's colour — back to plain grey ink — and carry that "selected colour" on the
  cell's FRAME instead, plus a PLAY BADGE styled identically to the play-ferry buttons' own PLAY icon, including the
  same velocity-flash animation. `BuildGridSelector.swift`'s `buildGridSelCell`: `rollTint` for the `selGrey` case is
  back to the unconditional `Color(white: 0.22)` (no `buildActiveFerry` read); a new `selectedHue` (same
  `buildActiveFerry.map { Color(hex: buildFerryHex($0)) } ?? Color(white: 0.22)` expression the notes used to read) now
  colours the `sel` frame stroke (was plain black for `selGrey`) AND drives a new play badge — `flashingIcon("play.fill",
  …)` (the SAME shared helper `roomsPlayFerry`'s own running-ferry icon uses, incl. its real-time velocity flash via
  `buildFlashLevel`/`meters.cellHitVel`), fed the cell's own `buildChainAuditionRow` strike index, bottom-trailing corner,
  shown only for `selGrey`. **ENGINEERING NOTE:** `flashingIcon` was `private func` in `BuildPage.swift` — Swift's
  `private` is file-scoped, so a same-type call from a different file (`BuildGridSelector.swift`, both extend `DiagView`)
  wouldn't compile; opened it to `internal` (dropped `private`) since it's now a cross-file shared helper, no behaviour
  change for its existing caller. UI-only, no test-target reach (GridUI, as always). **DEVICE-OWED:** the badge's size/
  corner placement at real grid-cell dimensions, and whether the border-recolour reads clearly against the light
  `buildSelectGrey` face it sits on.**
- **▶ OUT PIANO — fixed showing nothing, TWO bugs found chasing one report (2026-09-28, on `main`, `2eea46c`; macOS
  1141 green, iOS builds; DEVICE-owed). Paul, on the piano-swap feature above: "it doesn't work, I'm seeing nothing
  output," then "never showing, whichever method I use to get to the processor" — confirmed via a ferry actually
  playing. **BUG 1 (real, but not the actual cause here):** `Router.auditionRender` (press-and-hold single-cell
  preview, transport stopped) never tagged its emitted voices with `currentCellIndex`/`currentMachineIndex` at
  all — every audition voice inherited whatever a PRIOR real scene render last left in those globals (or -1). SEAL
  comet/`cellSoundVel`/`cellNoteHead`/the new `cellSoundingNotes` all key off `voices[].cellIndex`, so an audition
  was invisible (or misattributed) to every one of them, not just the new piano — fixed with the same save/set/
  defer-restore idiom `emitColumnRatchetPattern` already uses for the identical need. **BUG 2, THE ACTUAL CAUSE:**
  `buildPartColumnNow` (reused for the new `buildOutputCellIndex`) and its two playhead call sites
  (`roomsPartPlayhead`, `roomsCardRowPlayhead`) + `buildTruthStrips`' own `dynamic` flag ALL gated on `d.playing` —
  which `Diag.swift` documents explicitly as "the HOST transport flag (raw)". A ferry playing via FREE-RUN (no host
  transport running) made all four think nothing was playing. `d.effectivePlaying` ("host OR free-run — the UI's
  'is anything really playing' tell") already exists for exactly this distinction; these four just never used it —
  fixed together so the visible part-grid playhead, the card-header row playhead, and the OUT piano can no longer
  disagree about whether a free-run-only ferry is "playing." **DEVICE-OWED:** confirm the OUT piano lights up during
  a free-run ferry AND host-transport playback, and that the part-grid/card-header playheads now sweep during
  free-run instead of sitting frozen (a pre-existing symptom of bug 2 that predates this piano feature entirely —
  may explain other "the playhead doesn't move" reports if any were ever filed against free-run specifically).**
- **▶ PROCESSOR EDITOR — a one-shot cross-fade when the shown type changes (2026-09-28, on `main`, `b36026d`; iOS
  builds; DEVICE-owed). Paul: picking a different chain box (ARP→RATCHET) swaps the controls with nothing marking
  that it happened. ROOT CAUSE: the controls panel carries NO type identity of its own — the old header (emblem ·
  name · BYPASS/DELETE/CANCEL/DONE) was removed entire on 2026-09-10 as too heavy; the only surviving "ARP" vs
  "RATCHET" signal is a small tab label in a horizontal scroll strip above the panel, easy to miss once your eye is
  in the controls. Paul picked the transition over reviving a header. **FIX:** `ProcessorBox.body`'s one call to
  `typeParams(ft)` gained `.id(ft)` (a type change is a fresh view identity, not an in-place diff) +
  `.transition(.opacity)` + `.animation(.easeInOut(duration: 0.18), value: ft)` — a brief cross-fade catches the
  MOMENT the controls change. Lives in the shared component (not BUILD-specific), so it applies everywhere
  `ProcessorBox` renders. Explicitly NOT the same class of thing as the looping/strobing chain-box focus indicator
  Paul ruled out on 2026-09-08 — this is one-shot, tied to a real state change, not a resting-state animation.
  **DEVICE-OWED:** whether 0.18s reads as "caught it" without feeling laggy when tapping quickly between boxes.**
- **▶ PROCESSOR GRIDS — missing/wrong live sweeps fixed across 6 processors; the sweep redesigned as a pulse glow
  (2026-09-28, on `main`, `dce2d9c`; macOS 1141 green, iOS builds; DEVICE-eye owed on the whole look). Paul: "the
  processors have grids and many of them don't show the sweep... one important example is riff," plus "I don't like
  the appearance of the current sweep" — asked for an audit + visual proposals first (an artifact mockup: column
  wash · needle · pulse glow · header tick, against the honest current baseline), then picked **pulse glow**, and
  separately said not to bother with MUTE MATRIX's own (correct, just 4Hz-choppy) sweep. **AUDIT, then FIX (each
  reusing the ENGINE'S OWN resolve formula directly — spot-checked in Router.swift/Derivations.swift line by line
  before writing the UI clock, this project's own standing rule, not re-derived from the UI's own comments):**
  **RIFF** had ZERO live-sync anywhere (rank matrix, OCT lane, ACCENT/TIE/SLIDE all raw/static) — now calls
  `riffStepAt` directly, the SAME pure function `Router.emitRiffRow` calls, across all 5 non-stateful direction
  modes; DRUNK initially shipped deliberately unlit (its true position is per-cell RENDER-THREAD state this UI layer
  has no access to) — **fixed same day, see the DRUNK addendum below.** **VELOCITY** (both its lanes), **BURST** pattern, **TUTTI** pattern, and
  **CHORDS** degree matrix all had a sweep, but it always read the generic scene grid clock despite each having its
  own independently configurable rate/span (CHORDS' own code comment says it outright: "a chord per rate-tick, not
  per grid column") — each now gets a bespoke `StateMatrixClock` matching its real engine math (VELOCITY mirrors
  RATCHET's exact `driverNoteRate`-unknown guard for its NOTE clock mode; BURST's ROTATE is NEGATED relative to
  every other processor's convention — confirmed by reading `burstSliceAt`'s `(i − rotate)`, not assumed). **MOD's
  STEPS lane — found only while implementing, NOT in the original audit** — same gap, fixed by factoring the exact
  period math `modLiveCC` already used into a shared `modPeriodBeatsUI`, so the lane and the existing live CC marker
  can't disagree. **THE VISUAL:** the old thin top-edge line + faint background bump is replaced everywhere by ONE
  shared `pulseGlowOverlay` (a breathing white stroke + glow, ~1.67Hz, independent of tempo) — always plain white,
  never a second hue, so it reads consistently over whichever colour a processor's own cells happen to be; threaded
  through `stateMatrixRadio`, `sliderLane` (which also gained the same `clock:`/`liveColOverride:` bespoke-clock
  capability `stateMatrixRadio` already had), `toggleLane`, and a new `riffToggleLane` live hook. A new shared
  `liveCol(from:at:)` factors the "clock → live column" arithmetic that was previously hand-duplicated across
  `stateMatrixRadio` and `sliderLane` into one function, so a bespoke clock fed to two different widgets (VELOCITY's
  lane + its BYPASS toggle) can't disagree by construction. UI-only — no engine/render change, no new tests (nothing
  NEW to test; the engine formulas being matched are already covered, this is display code with no test-target
  reach, same as every prior playhead fix in this file). **DEVICE-OWED:** the pulse-glow legibility/rate on a real
  screen, RIFF's 5 direction modes actually tracking what's heard, and BURST's negated-rotate sweep against a real
  ROTATE drag. **DRUNK ADDENDUM (2026-09-28, same day, `5cea4db`; macOS 1141 green, iOS builds): Paul asked what it'd
  take to cover DRUNK too.** Checked the actual mechanism before proposing anything: `LiveTelemetry.beatAnchor`
  (`AudioUnitViewController.swift`) RE-SYNCS to the host's real beat position on a transport edge — it does NOT reset
  to zero — so a UI-side replay of the walk from an inferred restart point would silently diverge from the true one
  after the very first tick (the seed hash is tick-EXACT; being one tick off sends the whole subsequent walk down an
  uncorrelated path). That ruled out faking it client-side, confirming the earlier "can't safely replay" call was
  right, not just cautious. **FIX: read the true value instead.** `Router.riffDrunkPosAt(cellIndex)` — a plain array
  read of the existing `riffDrunkPos` state, mirroring `cellSoundingNotes`'s exact shape (the SAME UI-poll precedent
  the OUTPUT-piano entry below this one just established) — threaded through Kernel/`MidiSparkAudioUnit` as
  `pollRiffDrunkPos`, polled in `AudioUnitViewController`'s existing `editorOpen` block at the SAME cadence and SAME
  `buildOutputCellIndex` as the OUTPUT piano, into a new `buildRiffDrunkPos` → `ProcessorBox.riffDrunkPosLive`.
  RIFF's live-sweep closure reads it directly for DRUNK instead of computing a step. **Honestly capped, not
  shortcut:** the indicator jumps between columns at the diagnostic poll rate (~4Hz) rather than sweeping — the same
  ceiling MUTE MATRIX hit — because DRUNK's position genuinely isn't a predictable function of wall-clock time, so
  there's nothing smoother to extrapolate. No new tests (a UI-poll passthrough, same class as `cellSoundingNotes`
  itself, which also shipped untested — no test-target reach). DEVICE-OWED: confirm the jump reads as "the true
  position, updating slower" rather than as broken. **VISUAL FOLLOW-UP, same day (`31c88a1`; iOS builds): Paul —
  "I need only the selected cell to animate, not the entire column. I also want a playhead on the header of the
  column."** The per-cell glow lit every row at the live column (a `stateMatrixRadio` matrix is radio-per-column, so
  every OTHER row's cell there is off, but it still glowed) — narrowed to `live && on`, so only the actually-
  selected/sounding cell animates; applied to `stateMatrixRadio`'s main rows, CLOCK's GLIDE `extraRowCell` (shares
  the same live-column highlight, so it follows the same rule), and RIFF's own rank matrix (POLY mode can still
  glow several ranks at once — correctly, since several genuinely sound together there). OCT/ACCENT/TIE/SLIDE and
  the `sliderLane`/`toggleLane` lanes are untouched: one row = one cell already, nothing to narrow. New
  `playheadHeaderRow`: a thin strip above the grid reusing the SAME `liveCol`/`date` the cell glow reads (so the
  two can never disagree), showing a small chevron at the live column — SNAPS exactly, no fractional glide, since a
  RANDOM/DRUNK-class jump has no meaningful in-between position to interpolate through. One shared function, wired
  into `stateMatrixRadio` (covers RATCHET PATTERN/DEST/CLOCK/KILL STEP/BURST/TUTTI/LENGTH/CHORDS at once) and
  RIFF's rank matrix. **CAUGHT BEFORE SHIPPING, not after:** the first build of this actually FAILED — a
  `.frame(maxWidth:, height:)` call mixed two incompatible SwiftUI `.frame` overloads (this codebase's own
  convention is two chained `.frame()` calls, not one combined call) — a stale-looking background-task notification
  claimed success while the real log said `BUILD FAILED`; caught by tailing the actual log instead of trusting the
  notification, fixed, rebuilt clean before pushing. DEVICE-OWED: the header chevron's legibility/size, and whether
  a POLY-mode multi-cell glow at one column still reads clearly now that MONO's is down to one.**
- **▶ PROCESSOR EDITOR — the OUT truth strip is now a second piano, not a scrolling roll (2026-09-28, on `main`,
  `25dc00f`; macOS 1140 green, iOS builds; DEVICE-owed). Paul: IN/OUT were mismatched widgets (IN a piano of held
  pitches, OUT a piano-ROLL of drifting recent onsets) for what's really the same idea; make OUT a second piano.
  The existing OUT feed (`buildOutRoll`, an onset-only ring with no note-off tracking) structurally can't answer
  "what's held right now" — fixed by reading the render engine's OWN voice pool instead of re-purposing the onset
  trail: new `Router.cellSoundingNotes(cellIndex:)`, a same-shape sibling to the existing `cellSoundingVelSnapshot()`
  — a snapshot scan of `voices[].cellIndex`/`.active` (already tracking genuine hold-duration for note-off
  bookkeeping; no new render-side state, just a new read of what's already there). Threaded through Kernel/
  MidiSparkAudioUnit as `pollCellSoundingNotes`, polled into a new `buildOutHeld` array on the SAME `editorOpen` gate
  and cadence as the existing OUT-roll poll. **Needed its own cell resolution:** the existing focus-cell mechanism
  (the chain-flow comets) only covers chain audition, not a part row's processor — so `buildOutputCellIndex(at:)`
  mirrors `buildProcessing(at:)`'s own chain/part/none switch exactly (same rung/column gating), returning the
  `Snap.cells` index instead of a bool, so the OUT piano and the existing "is this instance processing" gate can
  never disagree about which cell is live. `buildInKeyboard` renamed `buildKeyboardStrip` (now serves both IN and
  OUT, 4 call sites); `buildOutStrip`/`buildRollCanvas` deleted (their only caller) — `buildOutRoll`/`OutMark` kept,
  the Stage Eye's separate OUTPUT lane still uses them. **DEVICE-OWED:** confirm the OUT piano lights the right keys
  against real playback (chain audition AND a part row), and dims/empties correctly when the editor's instance isn't
  the one currently sounding.**
- **▶ PART GRID — the multi-select playhead now sweeps every active row, not just the lead (2026-09-28, on `main`,
  `9232edf`; iOS builds). Paul: with MULTI selected, the playhead "doesn't always sweep over active cells when more
  than one is selected in a column" — three rows selected somewhere on the part, only two ever shown. ROOT CAUSE: a
  documented v1 shortcut from when multi-select shipped (2026-09-27) — the per-cell highlight (dimming + the white
  selection ring) already correctly used `buildActiveRungs` for every active row, but BOTH playhead renderers
  (`roomsPartPlayhead`, the grid's own sweep, and `roomsCardRowPlayhead`, the card/rail row selectors' mini-sweep)
  still read only the column's single "lead" rung. Since the lead is whichever row was MOST RECENTLY toggled per
  column, different columns can easily land on different leads — so sweeping across several multi-selected columns
  shows only whichever rows happened to be lead somewhere, never the full set together, exactly the reported symptom.
  FIX: both now read the same `buildActiveRungs(c)` the highlight already relied on — `roomsPartPlayhead` draws one
  bar per active row at the column's sweep position (a `ForEach`, was a single conditional bar); `roomsCardRowPlayhead`
  lights row `n` whenever `buildActiveRungs(c).contains(n)`, not only `r == n`. DEVICE-eye owed, as always.**
- **▶ ARP — the embedded Euclid mask removed, superseded by the standalone processor (2026-09-28, on `main`,
  `2063381`; macOS 1146 green, iOS builds). The arp-only `arpMask*` controls (HITS K/N, GAPS REST/TIE/CHORD, ROTATE,
  the CHORD-gap stab's OCT/LEN/VEL) were fully superseded by the newer standalone EUCLID MASK processor (`mask*`,
  landed 2026-09-27/28), which gates ANY driver — including ARP, via `[ARP → EUCLID MASK]` — and has since grown
  well past parity (INVERT, SPAN, CHANCE, ACCENT LAYER, FILL, CHORD PICK, none of which the arp-embedded version
  ever had). Paul asked for the redundant original removed. The one capability lost is WALK/WAIT (the walk advancing
  only on hits instead of marching through rests) — already an accepted, disclosed trade-off from when the
  standalone processor was built (a downstream fold can't reach a driver's own phase-index the way an embedded mask
  could) — nothing new lost by this cleanup. Removed: the `MachineParams`/`SnapParams` fields, `SnapshotBuilder`'s
  resolve, the `ArpMaskWalk` enum (confirmed zero other users), the engine block in `emitArpRow`, the ARP editor's
  UI controls, and the `AutoParamField` LFO-target cases — Swift's own exhaustive switches caught every call site
  that needed a matching removal. Two tests genuinely covering capability the standalone processor ALSO has (the
  chord-gap stab's OCT/VEL/GATE independence) were PORTED to chain `[ARP → EUCLID MASK]` instead of deleted, passing
  unmodified on first run — confirming the standalone fold's chord-gap math matches the removed version exactly;
  tests covering only the arp-embedded wiring itself (including one exercising WAIT, which has no replacement) were
  removed outright. **FLAGGED, not fixed here:** the standalone EUCLID MASK processor has NO param-LFO targets
  registered anywhere, unlike the version it replaces (which exposed HITS/ROTATE/CHORD-OCT/CHORD-LEN to the `∿`
  modulation system) — a real capability gap, found while removing the old version, separate scope to restore.
  **LFO RESTORED (2026-09-28, `0b41225`; macOS 1147 green): Paul asked for the flagged gap fixed.** ROOT CAUSE of why
  this wasn't a one-line UI wire-up: `applyParamLFO` (the `∿` engine) resolves every non-`"arpRate"` target through
  `AutoParamField` — the SAME enum the removal above correctly stripped its old `arpMask*` cases from. So restoring
  the control needed NEW `AutoParamField` cases (`.maskK`/`.maskRotate`/`.maskChordGate`/`.maskChordOct`) pointing at
  the standalone processor's own fields, plus the five GridUI switches that seed/format/edit an LFO's FROM/TO value
  by target-name string (`lfoLabelText`/`lfoEndpointControl`/`lfoFmt`/`lfoSeedFrom`/`lfoSetBase`), plus `lfo:` wired
  into the four `field()` calls themselves. **Caught by the compiler, not a hand-check:** two more exhaustive
  switches in `Tests/EffectiveParamsTests.swift` locking `AutoParamField`'s key list and clamp bounds needed the
  same 4 cases — the build failed until both were extended, exactly the safety net exhaustive switches exist for.
  +1 RouterTest (`testEuclidMaskKLFOModulatesDensity`, restoring the coverage the removed
  `testArpMaskKLFOModulatesEuclidDensity` had, chained after an ARP driver on the standalone processor's own `maskK`).**
- **▶ CHAIN EDITOR — fixed a stale edit-slot showing an empty box's PASSGATE identity after a drag-reorder
  (2026-09-28, on `main`, `1585c28`; iOS builds, macOS 1147 green). Paul: "a pass gate processor sometimes shows
  when it's not part of the MIDI chain." Root-caused, not guessed: an empty/placeholder chain box is INTERNALLY
  represented as a bypassed PASSGATE slot (`buildPassthroughSlot`, `buildIsEmptySlot` — this is load-bearing
  plumbing, not incidental). `buildChainMoveSlot` (drag-to-reorder) vacates the DRAGGED-FROM box into exactly that
  placeholder, but never updated `buildEditSlot` — so if the user was editing the box they then dragged elsewhere,
  `buildEditSlot` kept pointing at the now-empty original position. The main processor panel's render guard
  (`roomsProcessorCardAt`) only checked array bounds, not emptiness — unlike every OTHER reader of a chain slot (the
  tab strip, the chain-box grid, the drag ghost), which already guard with `buildIsEmptySlot` — so the panel (and
  "the eye" diagnostic view, the same gap) showed that empty box's PASSGATE identity as if it were a real processor,
  purely because the user reordered a DIFFERENT (the moved) processor. **FIX:** `buildChainMoveSlot` now follows
  `buildEditSlot` to the moved processor's new position; added the missing `buildIsEmptySlot` guard to both
  previously-unguarded readers as defense in depth, matching the convention every other call site already follows.
  UI-only; DEVICE-eye owed to confirm the reorder-while-editing flow now keeps the right card open. **SEPARATE ASK,
  NOT YET ACTED ON:** Paul also asked to remove the PASSGATE processor entirely. Flagged back to him rather than
  done blind: PASSGATE is BOTH a user-facing storefront card (the "PASSES" card — pass-gated laps 1–4) AND the
  engine's internal "this chain slot is empty" sentinel (`buildPassthroughSlot`/`buildIsEmptySlot`, `isHoldTailChain`,
  `cellMode`'s pass-based silent/identity logic) AND a generic "identity hold" utility used throughout the test suite
  (~80 references in `RouterTests.swift` alone, most nothing to do with PASSGATE's own feature). Removing the
  user-facing card is a small, safe change; removing the TYPE itself would need a replacement sentinel mechanism and
  touch dozens of call sites plus most of the test suite — asked Paul which he actually means before touching either.**
- **▶ PASSGATE — REMOVED ENTIRELY, the whole type (2026-09-28, on branch `refactor/remove-passgate`, `2839240`; macOS
  1142 green, iOS builds). Direct follow-through on the entry above: Paul answered the three-way flag — "the whole
  type, engine included"; cut factory scene 9 from the sixteen, don't replace; delete test session T13 outright.
  **DECODE SAFETY:** `ProcessorType.passgate` → `.empty`, raw string `"PASSGATE"` KEPT — an old saved cell of that
  type still decodes, landing on `.empty`, now a plain inert passthrough (exactly right: the gating it used to do no
  longer exists to preserve). **DELETED, not renamed (the feature itself):** `MachineParams.passes` ·
  `SnapParams.passMask` / `effectivePassMask` · `cellMode`'s pass-mod-4 branch (`.empty` now just joins the
  always-`.identity` bucket; `cellMode`'s signature dropped its now-pointless `passMask`/`pass` params — 8 call
  sites in Router.swift/Kernel.swift simplified) · the GridUI "PLAY ON PASS" editor row + its self-clocked playhead
  (`livePass`/the dead `passHead` field, found and removed in passing) · the storefront "PASSES" card ·
  MacroAuthoring's dedicated PLAY-ON-PASS binding (folded into the existing bypass-only catch-all bucket every other
  discrete-param type already uses). **RENAMED (sentinel + generic-fixture uses, compiler-driven sweep across ~25
  files):** `buildPassthroughSlot`/`buildIsEmptySlot` and their AU-side/EditPage.swift/Dice.swift twins,
  `isHoldTailChain`'s tail-type list, ~20+ "give me an inert machine" test fixtures. Roster lists that used PASSGATE
  as one of several types to hammer/exclude (FuzzTests' type roster, ChaosDriver's edit-fuzz roster, Dice's factory-
  chain generator's "NO PASSGATE" exclusion, BuildSelfTest's no-stuck-notes roster) had the entry DROPPED rather than
  renamed — `.empty` isn't a real processor a user or generator would ever produce, so it doesn't belong in a "hammer
  every real type" list either. **SCOPE SURPRISE, caught mid-implementation, not pre-planned:** the plan assumed
  only scene 9 used the `pass()` scene-builder DSL helper; grep found THREE more call sites (UNDERTOW, THE LOOP THAT
  ISN'T, PACIFIC) — two used it only in its default all-open state (a plain sustain in musical terms, so converting
  to the new `thru()` helper — same helper, `.empty`-typed, no mask param since none exists anymore — is
  byte-identical), but PACIFIC's "wine" voice genuinely alternated every 2nd pass as a deliberate texture (documented
  in `factory-scenes.md`'s own COLOURS line). No replacement mechanism exists for that alternation now — `wine` was
  converted to a continuous sustain, an honest degradation flagged here and in the scene's own doc entry rather than
  silently absorbed. **ROUTERTESTS.SWIFT (~38 references across 36 functions) forked out** rather than swept blind —
  many asserted the pass-mod-4 gating mechanism as their actual subject, not just used PASSGATE as a fixture. Per-test
  triage: 2 DELETED (`testArpThenPassgateGatesPassZero`, `testPassgateGatesByPassInThePlayingPath` — nothing left to
  assert once the mechanism is gone); 13 SUBSTITUTED `.chance` at `probability: 1.0`/`0.0` for PASSGATE's open/closed
  states (verified exact, not seed-dependent, against `Derivations.chancePasses`'s own hard clamp at the
  probability extremes, before relying on it — not assumed); ~20 mechanical `.empty` renames incl. a shared
  `passgateMachine` fixture helper renamed `holdMachine`. **FACTORY SCENES renumbered 10-16→9-15** in both
  `SceneFactory.swift` (code) and `Docs/factory-scenes.md` (every cross-reference re-derived from the actual
  old→new mapping, not just the headers — caught ALT EGO's own device-test procedure in `Docs/test-procedures.md`
  still citing its OLD scene number 14, now 13, a real cross-doc drift that a header-only renumbering would have
  missed). `Docs/pending-tasks.md` and `Docs/manual/manual-skeleton.md` had their own PASSGATE mentions fixed
  (a stale future-task example list, a manual glossary entry for a feature that no longer exists). **FLAGGED, not
  touched:** `midispark-spec-v2.8.md`/`v3.0-delta.md` still describe PASSGATE's pass-mask behaviour in several
  places — treated as a separate, larger spec-contract editorial pass rather than surgery-by-the-way; `feature-
  status.md` is a self-described already-stale redirect notice, left alone; `status-log-archive.md`/`codebase-
  review-2026-08-16.md`/`router-design.md`/`migration-tree-routing.md` are established-historical and never
  retroactively edited by this project's own convention. **DEVICE-OWED:** confirm no chain anywhere still shows a
  "PASSES" card; an old saved doc with a real PASSGATE cell opens as a silent inert passthrough, not a factory-reset
  or a decode error; PACIFIC's wine sustaining continuously instead of alternating every 2nd pass reads as an
  acceptable finale-scene change, not a loss.**
- **▶ EUCLID MASK — CHORD PICK gains BOTTOM2/TOP2 (2026-09-28, on `main`, `9d38406`; macOS 1141 green incl. fuzz,
  iOS builds; DEVICE ear/eye owed). Paul: add bottom-two/top-two to CHORD PICK. Judgment call, flagged rather than
  asked: rather than extend the SHARED `EuclidPick` enum (also used by the standalone EUCLID driver's own PICK),
  introduced a DEDICATED `MaskChordPick` enum (ALL·LOW·HIGH·BOT2·TOP2·CYCLE·RANDOM) — BOT2/TOP2 strike a PAIR of
  notes, which the driver's own `strikeChord(onlyIndex:)` (one pool-rank at a time) can't express, so reusing the
  enum would have forced an unrelated change onto the driver for a feature Paul didn't ask to touch. Generalized the
  fold's single optional pick index into an INCLUSIVE RANGE (`lo...hi`) — ALL/LOW/HIGH/CYCLE/RANDOM are a range of
  one, BOT2/TOP2 a range of two, one application path for all seven. **CAUGHT WHILE WRITING THE FIX, not by a test:**
  the naive range construction (`max(0,lo)...min(count-1,hi)`) can build an INVALID `ClosedRange` (Swift traps on
  lower > upper) if `count` were ever 0 by the time the range is applied — guarded by checking `count > 0` BEFORE
  constructing the range, not just filtering after; pinned down with a dedicated regression test (BOT2/TOP2 against
  a single held note collapses to one note cleanly, not a crash) rather than left as an unverified guard. +2
  RouterTests. **DEVICE-OWED:** BOT2/TOP2 actually sounding like the intended voicing against a real chord.**
- **▶ RIFF — 6 playhead direction modes: FWD/REV/PENDULUM/PING-PONG/RANDOM/DRUNK (2026-09-28, on `main`, `92042df`;
  macOS 1146 green, iOS builds; DEVICE ear owed). Paul asked for an option to override how the RIFF playhead travels,
  giving precise worked examples for all 6. Found along the way: today's `RiffDir.pingpong` already matched the new
  spec's PENDULUM exactly (hand-verified — bounces, each end played once, cycle 2n−2, n=2 degenerates to FORWARD) —
  the same class of bug as RATCHET PATTERN/DEST/the ARP-rate LFO before it, a control whose name didn't describe its
  own behaviour. **Fixed for free, no migration:** `.pendulum` KEEPS the old `"PING-PONG"` raw value (old saves
  decode byte-identical; the editor now correctly labels them PENDULUM instead of the wrong PING-PONG); the
  genuinely-new bounce-TWICE mode gets a fresh raw value (`"PONG"`) as `.pingpong`; a `displayLabel` splits the
  UI-shown name from the persistence key so both read right. FORWARD/REVERSE/PENDULUM/PING-PONG/RANDOM are all pure
  functions of the existing `raw` tick index — no new state, SPAN re-anchor applies uniformly to all five; RANDOM
  reuses `splitmix64Mix` (the same primitive `ArpPattern.randomOnce` already uses) keyed by a new per-instance
  `riffDirSeed`. **DRUNK is the one genuinely stateful mode** (its own spec: "position carries across cycles") —
  runs against this project's "derived, never accumulated" invariant. Resolved by following the EXACT existing
  precedent for this class of state (DEAL/ALT's per-cell counters, `Router.swift` ~315) rather than inventing
  something new — disclosed, not waved through as pre-approved: the codebase's own architecture review
  (`Docs/codebase-review-2026-08-16.md`, finding A1) already flags that class of state as a known, UNDISCHARGED
  limitation (not replay-exact across a mid-phrase seek/loop), not a blessed exception — this is a deliberate third
  instance of an accepted trade-off, named honestly as such. Keyed on `tick`, NEVER `raw` (a design correction caught
  during planning, not shipped wrong first) — `raw` resets at every SPAN boundary, so keying off it would make the
  walk silently re-sync mid-cycle, contradicting "carries across cycles" outright; `tick` is monotonic and
  SPAN-oblivious by construction. Reset alongside DEAL/ALT on the transport-edge "fresh play" trigger, never on
  panic. A BIAS control (`-1...1`, 0 = neutral, the exact `chanceTilt`/`velTilt`/`bipolarSlider` convention) tilts the
  walk's −1/0/+1 weights via a squared tilt: bias=0 → uniform ⅓ each ("wanders evenly"); bias=+1 → 0%/20%/80%,
  forward-dominant but never deterministic ("Forward with stumbles", hand-verified both extremes before shipping).
  +6 RouterTests (literal n=8 sequences for PENDULUM/PING-PONG, the n=2 PENDULUM=FORWARD edge case, RANDOM seed-
  repeatability + range, DRUNK bounds/step-size across 4 seed·bias combos, DRUNK reset-on-transport-edge). One test
  explicitly NOT shipped rather than shipped vacuous: a SPAN-obliviousness regression guard for DRUNK never showed
  ANY span effect on ANY mode (including FORWARD) under the test harness's `forceColumn:0` bypass — a test-
  infrastructure interaction, not a code defect (the engine change was verified by direct reading, independently,
  twice), flagged inline at the deletion site rather than hidden. Plan: `~/.claude/plans/flickering-dazzling-floyd.md`.
  **TIE LOOKAHEAD FIX (2026-09-28, `04459d3`; macOS 1148 green): Paul asked to fix the disclosed TIE limitation
  above.** RIFF's TIE run always checked array-index `step+1` for "what plays next" — already wrong for REVERSE
  (whose true next step is `step-1`), meaningless once PENDULUM/PING-PONG/RANDOM/DRUNK made "next" stop being a
  fixed offset at all. FIX: factored the 5 non-DRUNK modes' step formula out of `emitRiffRow`'s inline switch into a
  pure `riffStepAt(dir:raw:steps:seed:)` (Derivations.swift) — used for BOTH the current tick's step and the TIE
  lookahead's `raw+1, raw+2, …`, so the two can never disagree (the RATCHET/DEST class of bug: a lookup and its
  lookahead drifting apart). DRUNK gets `riffDrunkPeek` — a NON-MUTATING simulation of the walk forward from its
  current position using the SAME pure per-tick `riffDrunkDelta`, exact (not a guess) since replaying the identical
  future tick indices later reproduces precisely what the real walk will do. Hand-verified against the exact REVERSE
  bug before writing the fix or the test: steps=4, tie on step 2 (REVERSE's true next step after step 3) — the old
  formula checked step 0 (untied, no extension), the new one correctly finds step 2 tied; FORWARD's formula is
  provably byte-identical (same arithmetic, `s ≡ raw (mod steps)` either way). +1 RouterTest
  (`testRiffTieRespectsReverseDirection`, asserting fewer note-ons with the tie painted on REVERSE's real next step
  vs. without it — would have failed under the pre-fix code). SLIDE's own `prevStep = step - 1` lookup (Router.swift,
  a few lines below TIE) has the EXACT same forward-adjacency assumption, in the other direction — noticed while
  fixing TIE, NOT fixed here (Paul asked specifically about TIE), flagged as a likely next ask.
  **SLIDE FIX (2026-09-28, `9561d16`; macOS 1149 green): Paul asked for the flagged SLIDE bug too.** The mirror image
  of the TIE fix: SLIDE's "was the PREVIOUS step a slide" check always looked at array-index `step-1` — already
  wrong for REVERSE (whose true previous step is `step+1`) — so a slide armed at one step could go un-cleared once
  the real next note struck, leaving portamento wrongly armed into a later, unrelated note. Non-DRUNK modes reuse
  `riffStepAt(raw-1)` — the identical pure formula one tick EARLIER, so it can't disagree with the current step by
  construction. DRUNK can't be algebraically un-walked (a reflected random walk isn't invertible from its current
  position alone, unlike TIE's forward case which could reuse `riffDrunkPeek`) — so its previous position is simply
  REMEMBERED instead: new `riffDrunkPrevPos` (Router.swift, beside `riffDrunkPos`), written by `riffDrunkStep` right
  before it moves, reset alongside the walk's other state on a fresh play. Hand-verified against the same REVERSE
  shape as the TIE fix before writing the test: steps=4, slide on step 1 — REVERSE's true next step (0) now
  correctly detects it and clears the portamento; the old lookup checked step 3, found nothing tied, left it armed.
  +1 RouterTest (`testRiffSlideRespectsReverseDirection`).**
- **▶ EUCLID MASK — INVERT, SPAN, ACCENT LAYER, FILL, PROBABILITY, CHORD PICK (2026-09-28, on `main`, `2a54d5d`;
  macOS 1140 green incl. fuzz, iOS builds; DEVICE ear/eye owed). Asked what else the design space supported; Paul
  picked six to build now, in the priority order agreed: INVERT + SPAN first (cheap, closed a real consistency gap),
  then ACCENT LAYER (pencilled in since 2026-09-15), then FILL, PROBABILITY, CHORD PICK. All six are additive-
  Optional fields on the SAME processor — no new chain position. **INVERT** mirrors the sibling EUCLID driver's own
  toggle exactly. **SPAN** re-anchors the K-of-N ordinal to 0 every N notes, sized by the DRIVER's own step (mirrors
  KILL STEP sizing its own span ladder by its own rate) — EUCLID MASK was the one pattern processor in the whole
  codebase (RIFF/EUCLID/RATCHET PATTERN/KILL STEP/CLOCK all already had this) that had shipped without it. **FILL**
  overrides the mask for a whole pass every N passes, reusing `pass` — already a parameter of `emitDriverNote`, the
  SAME authoritative lap counter PASSGATE gates on — no new counter needed. **PROBABILITY (CHANCE)** is an Elektron-
  style trig condition layered on the deterministic skeleton: it can only DEMOTE a hit to a gap, never promote a gap
  to a hit (seeded on the ordinal `g` alone, mirroring HUMANIZE's own inline `splitmix64Mix` idiom — replay-exact, no
  accumulated state), and is skipped entirely on a fill pass. **ACCENT LAYER** is a second, fully independent K/N/
  ROTATE test sharing the SAME `g` as the gate (so a SPAN re-anchor keeps both patterns' relative phase stable) —
  boosts velocity additively on its own hits, like RIFF's own ACCENT lane; K=N (off) by default, matching the gate's
  own no-op convention. **CHORD PICK** restricts a GAPS=CHORD stab to specific chord note(s) — reuses `EuclidPick`
  (ALL/CYCLE/LOW/HIGH/RANDOM) and mirrors the sibling EUCLID driver's own PICK resolution (down to the same RANDOM
  seed constant), keyed on "gaps before `g`" — derived from the ALREADY-TESTED `euclidMaskHitsBefore` via simple
  arithmetic (`g − hitsBefore(g)`), so no new pure function was needed. Ordering inside the fold, precisely: SPAN
  re-anchors `g` → INVERT flips the base pattern → FILL overrides everything for the pass → CHANCE can only demote a
  hit → GAP/HIT resolves as before (now PICK-aware) → ACCENT applies independently in the final emit loop, right
  where TIE's own gate-extension already lands. +6 RouterTests, one per feature, each an inequality/property
  (INVERT's output is the exact complement of the non-inverted run; SPAN < the pattern's own N changes the onset set
  vs FREE; an active ACCENT strictly raises peak velocity; FILL strictly increases note count over several passes;
  CHANCE never increases note count and is provably unreachable with the gate off; CHORD PICK's LOW/HIGH strike only
  one note per gap while ALL strikes the whole chord) + fuzz coverage hammering FILL/CHANCE against TIE/CHORD (the
  paths most likely to leak a stuck voice). Plan: `~/.claude/plans/stateless-tickling-flask.md`. **DEVICE-OWED:**
  CHANCE's feel at various probabilities, ACCENT audibly popping against the base hits, FILL reading as a turnaround
  not a glitch, CHORD PICK's CYCLE/RANDOM actually rotating through a real chord.**
- **▶ KILL STEP — MUTE + PAUSE step behaviors alongside the original DROP (2026-09-27, on `main`, `f35b595`; macOS
  1134 green incl. fuzz, iOS builds; DEVICE ear/eye owed). Direct follow-through on the reminder set the day EUCLID
  MASK landed: Paul asked to plan whether KILL STEP's one boolean ON/OFF row could grow MUTE ("the step advances but
  doesn't play") and PAUSE ("stops it advancing for a configurable number of steps"), and whether the idea works/is
  musical. Confirmed both — MUTE is the standard step-sequencer mute (a hole, pattern length unchanged); PAUSE has
  real precedent (Elektron trig-condition holds, Metropolix's PAUSE/TIE stage type) — then ratified two calls via
  AskUserQuestion: PAUSE freezes/holds (nothing new triggers; whatever's sounding just rings on — NOT a retrigger/
  stutter) and its hold length is ONE global setting, not per-step. **BUILT:** the boolean row becomes a 4-state
  `KillStepMode` (ON·MUTE·DROP·PAUSE) per step. DROP is the original mechanism, unchanged. MUTE counts exactly like
  ON for the TRANSFORM (the downstream clock advances through it normally) — its whole effect is a new per-note FOLD
  in `emitDriverNote`, the identical shape EUCLID MASK's REST just shipped with, keyed on the note's real onset
  against KILL STEP's own rate (`precedingKillStepMuted`, scanning `0..<driver` like `driverClockBeat` itself).
  **PAUSE broke the old one-line closed form** (`value = lap·steps + onIdx[n mod k]` assumed every real column maps
  to exactly one local step; a hold needs SEVERAL real columns to map to the SAME frozen value) — replaced with a
  small table PRECOMPUTED once per snapshot publish (`killStepResolveTable`, Derivations.swift), off the render
  thread entirely; `killStepPhase`/`killStepPhaseInverse` now do a cheap `table[n mod columnsPerLap]` lookup instead
  of deriving the cycle live. Proven byte-identical to the original formula whenever nothing is MUTE/PAUSE by
  rerouting all 5 pre-existing `killStepPhase` tests through the new table unchanged (same assertions, same
  results). The table is SHARED between `SnapshotBuilder`'s resolve and GridUI's live-playhead preview (one
  function, so the lit cell and the audible step can't drift apart — the standing RATCHET PATTERN/DEST lesson).
  `killStepEnabled: [Bool]?` stays as a decode-only migration source (true→ON, false→DROP), even though nothing had
  shipped with it device-verified yet — costs nothing to keep. **UI:** the boolean `toggleLane` row is replaced with
  `stateMatrixRadio` (the SAME one-of-N-per-column widget RATCHET PATTERN/DEST/LENGTH already use) — which gained a
  new optional `liveColOverride` closure (mirroring `toggleLane`'s own `live:` shape) so KILL STEP's playhead can
  still call `killStepPhase` directly instead of the widget's generic rotate-clock math (that generic math can't
  express a freeze — using it here would have been a real regression from yesterday's playhead fix). Added a PAUSE
  LEN control. **CAUGHT BY THE TEST SUITE, not guessed (this session's own standing rule):** a first draft's inverse
  round-trip test assumed exactness everywhere, mirroring the pre-existing sweep test's own doc comment — but PAUSE
  makes the forward map genuinely NON-INJECTIVE by design (every real column across a hold maps to the SAME frozen
  value, so a beat landing on the hold's 2nd/3rd column can only invert back to its 1st) — 64 failures, traced to
  the test's premise being wrong, not the implementation; fixed by replacing the blind sweep with the explicit
  "inverts to the first occurrence" case, the SAME policy the pre-existing DROP-gap test already modeled explicitly
  rather than swept. **FLAGGED, not built (scope, not a bug):** MUTE only has an effect when KILL STEP PRECEDES the
  driver it retimes (`[KILL STEP→ARP]`, its own generation) — in the OTHER existing KILL STEP shape
  (`[ARP→KILL STEP→DEST]`, retiming a downstream fold consumer's own clock) there's no note-generation event left at
  KILL STEP's own position to suppress, so MUTE is a no-op there; DROP/PAUSE work in both positions since they're
  pure time-transforms. +3 RouterTests (MUTE keeps timing but silences one note · PAUSE makes several consecutive
  arp ticks land on DEST's same emitter, mirroring `testKillStepTransformsDestsOwnRoutingClock`'s own technique ·
  the legacy `killStepEnabled` migration is byte-identical to authoring the equivalent `killStepMode` directly) + 4
  new DerivationsTests (MUTE counts like ON for timing · a hold freezes for its exact length · the inverse picks the
  first occurrence · all-columns-of-a-hold read the identical value) + fuzz coverage (hammers PAUSE especially, the
  one genuinely new way a driver's own tick search could misbehave). Plan: `~/.claude/plans/stateless-tickling-
  flask.md`. **DEVICE-OWED:** the 4-state matrix's legibility, MUTE actually leaving a clean silent hole vs. DROP's
  compaction, and PAUSE reading as a hold/breath rather than a glitch.**
- **▶ SELECT GRID — the picked cell now survives a trip through PART (2026-09-27, on `feature/ferry-row-
  unification`, `46c0b2d`; iOS builds; DEVICE eye owed). Paul: pick a SELECT cell → open PART → come back → wants the
  SAME cell still in focus. ROOT CAUSE: `roomsPartSetup` always calls `buildRoomsSetActiveSide` to focus a part row,
  which explicitly nils `buildGridSelSel` — the browse-cell pick and a ferry-row focus share ONE underlying value
  (`buildSelectSource`, "one thing active", the 2026-09-06 desync fix) — so every PART entry silently discarded
  whatever was picked on SELECT. FIX: new `buildGridSelLastPick` snapshots the outgoing pick (nil included, so a
  deliberate deselect before leaving isn't resurrected) the moment PART claims the slot; `roomsSelectSetup` restores
  it on a plain return (skipped when a playing part's cell is being carried over instead — `carryFromPart`, an
  existing, more relevant behaviour for that case). Restoring the pick also resumes its chain audition for free,
  since `roomsSyncVoice` already ties "a cell is selected" straight to "it's auditioning."**
- **▶ EUCLID MASK — the arp-only mask pulled into a standalone downstream processor (2026-09-27, on `main`, `d6bb40d`;
  macOS 1116 green incl. fuzz, iOS builds; DEVICE ear/eye owed). Paul asked whether the ARP EUCLID MASK feature
  (`arpMask*` — a K-of-N Bjorklund pattern with GAPS·WALK·ROTATE, baked inline into `emitArpRow`) could work as its
  own chain processor, usable downstream of ANY driver, not just ARP. Worked the architecture out live: GAP
  (REST·TIE·CHORD) + ROTATE fit the codebase's existing per-note downstream-FOLD seam (`isModifierFoldable` +
  `emitDriverNote`) — the same one SHIFT/HUMANIZE/VELOCITY/RATCHET's fold already use — so pulling them out reaches
  the WHOLE driver roster (ARP/RIFF/STRUM/RATCHET/EUCLID-as-driver/…) for free. WALK's WAIT mode does NOT fit that
  seam — it doesn't reshape a note it's handed, it overrides which note the driver picks in the first place (feeds
  `euclidMaskHitsBefore` into `arpPick`'s `phaseIndex`), a decision already made before any fold sees the note.
  Traced WAIT's actual mechanism to the SAME renumbering `killStepPhase` already does — it belongs to the OTHER
  existing seam, the upstream beat-transform family CLOCK/KILL STEP use (`driverClockBeat`), which would need the
  processor to sit BEFORE its target driver instead of after (the opposite position from GAP/CHORD/ROTATE). Paul:
  "I'm happy to drop wait as an option." **BUILT:** `ProcessorType.euclidMask` — not `isDriverType`, joins
  `isModifierFoldable`; a new fold block in `emitDriverNote` keyed on the note's ordinal against the upstream
  driver's own rate (mirroring VELOCITY's `driverStep`), reusing `euclidMaskHit`/`euclidMaskTieRun` unchanged; new
  `mask*` fields mirrored on BOTH `MachineParams` and `SnapParams` (+ the `SnapshotBuilder` resolve — missing this
  the first time round is what the macOS build caught immediately); a new GridUI editor (the ARP mask block minus
  WALK); a DYNAMICS storefront card; `cellMode` classifies it `.identity` (same bucket as VELOCITY/DEST/CLOCK/KILL
  STEP — verified via `applyStage`'s `default:` fallthrough, not assumed). ARP's own embedded `arpMask*`
  fields/editor are UNTOUCHED — this is additive, not a migration. +7 RouterTests (REST drops gap notes · TIE
  extends the gate across gaps, not just count · CHORD stabs the gap with more note-ons · ROTATE changes WHICH
  ticks gate, not the count · K=N is byte-identical to the arp alone · folds onto RIFF too, proving it's
  driver-agnostic · a lone instance is a no-op exactly like an empty chain, guarding the AVOID-class "silently
  emits nothing standalone" bug) + fuzz coverage (hammers the CHORD note-injection path especially, the most likely
  place to leak a stuck voice). **CAUGHT DURING THE BUILD (own dead-code survey, not guessed):** `MacroAuthoring.
  swift`'s per-processor macro-bindable-params switch is exhaustive via a big bundled catch-all case
  (`case .octave, .transpose, …, .killStep:`) that a naive grep for `"case .killStep"` misses (killStep isn't the
  FIRST case in that line) — cost one extra build round-trip; added `.euclidMask` to the same bucket (its config is
  per-step/discrete, not a simple macro-foldable scalar, matching KILL STEP's own reasoning). **PLAN:**
  `~/.claude/plans/stateless-tickling-flask.md`. **DEFERRED (Paul 2026-09-27, logged in `Docs/pending-tasks.md` +
  a memory file):** once this is device-verified, raise whether KILL STEP itself should gain selectable
  disabled-step behaviors (DROP/MUTE/PAUSE) instead of one fixed behavior — a direct spin-off of this same
  conversation. **DEVICE-OWED:** the new card's editor legibility, GAP=CHORD actually sounding right downstream of
  a non-ARP driver (e.g. `[RIFF→EUCLID MASK]`), TIE's extended-gate feel, ROTATE's control.**
- **▶ SELECT GRID — picked-cell notes wear the selected ferry's colour (2026-09-27, on `feature/ferry-row-
  unification`, `504416f`; iOS builds; DEVICE eye owed). Paul: the picked-but-uncommitted SELECT cell's face was
  inverting (a bright background with dark-grey notes) — wants the notes coloured instead. `buildGridSelCell`'s
  `rollTint` (BuildGridSelector.swift) now reads `buildFerryHex(buildActiveFerry)` — the SAME "selected colour" the
  ferry-row selector glow already uses (`roomsPlayFerry`'s header-bar emanation) — instead of `Color(white: 0.22)`,
  when the cell is picked (`selGrey`). Live: tapping a DIFFERENT, unselected ferry's own selector (`buildActivateFerry`)
  re-points `buildActiveFerry`, so the notes recolour with it at once. Unaffected: picking a different SELECT cell or
  deselecting falls out of the `sel`/`selGrey` branch entirely, reverting to the plain grey face exactly as before —
  and a COMMITTED (named) cell's roll stays white on its own machine-hue background, untouched (it was never
  "inverted" to begin with). DEVICE-OWED: legibility of a ferry hue as ink against the still-unchanged bright
  `buildSelectGrey` card background — Paul asked only to recolour the notes, not the card, so that pairing is
  unverified off-device.**
- **▶ FERRY ROW UNIFICATION — Stage 1: dead-code removal (2026-09-27, on `feature/ferry-row-unification`, `f689649`;
  macOS 1109 green, iOS builds). Paul: background ferries should play polyphonically, not the mono reduction
  `buildFlattenFerry` forces on them today — and questioned why the engine has a shared rows-0-7 concept at all.
  Ratified target (plan `flickering-dazzling-floyd.md`): 8 ferries × 4 dedicated engine rows each, always live, no
  active/background distinction, plus a per-ferry SINGLE/MULTI row-select toggle. Stage 1 clears the ground: deleted
  three confirmed-dead layers, each traced to zero live producers before removal — the pre-ferry "PIECE" deployed-
  arrangement grid (`performCells`/`buildPerformPart`, only ever written by snapshot/undo restore; no live gesture
  reaches it since the Room enum dropped to SELECT/PART only), the superseded independent play-cell grid
  (`playCells`/`playSel`), and the tap mute/solo/alt bitmask cluster (`tapMuteMask`/`soloCellMask`/`tapAltMask`,
  structurally capped at 64 bits `col*8+row` and traced end-to-end — `applyTapOverlay` has zero callers, and the one
  theoretical solo-mask path is defensively zeroed by `buildPublishScene`'s own `clearMachineSolo()` every publish).
  `soloEmitterMask`/the live emitter-strip SOLO buttons are untouched — confirmed a separate, live feature despite
  sharing call sites. Ported 5 BuildSceneLogicTests that used `performCells` as scaffolding for the still-live
  chain-audition-fallback logic to use `stagingCells` instead, rather than losing that coverage.
  **STAGE 2 — widen the row axis (2026-09-27, `0901d9b`; macOS 1109 green, iOS builds):** `Snap.ferries=8`/
  `rowsPerFerry=4`/`ferryRowBase(t)=t×rowsPerFerry` land as the PERMANENT per-ferry addressing, replacing
  `playLayerRowBase`; `BuildPart`'s row storage shrinks 8→4 to match the already-4-row `roomsPartGrid` UI. Caught by
  testing, not guessed: naively relocating a background ferry's mono row from `8+t` to `ferryRowBase(t)` collides
  with the still-untouched STAGING write path at `ferryRowBase(0)=row 0` — `testPlayGridComposesStartedColumnsAs-
  ContinuousVoices` failed asserting row 0 empty when ferry 0's background content now legitimately lived there.
  FIX: a TRANSITIONAL `Snap.stagingRowBase = ferries×rowsPerFerry` (32) reserved past every ferry's block, where the
  still-live staging pass parks until Stage 3 unifies the composer — `Snap.rows` is 36 for this stage only, settling
  to 32 once Stage 3 deletes the reservation.
  **STAGE 3 — one composer loop, every ferry alike (2026-09-27, `0233d34`; macOS 1116 green, iOS builds):**
  `composeSceneMeta` no longer distinguishes an active bench ferry from a background one — every ON+audible ferry
  composes from its own `BuildPart` into its own dedicated `ferryRowBase(t)` block, every publish; `buildPublishScene`
  captures the active ferry fresh from live @State (`buildCaptureBenchPart`, already used for this — verified it
  already carries every field the unified composer needs: rate/length/loopCols/receiver/emitters/rowReceiver/
  rowEmitters) and reads every other ferry's stored part directly. **This is the structural change that actually
  makes background polyphony possible** — a background ferry's content no longer gets flattened to one machine per
  column before it can play. Traced before relying on it: `buildStagingPlaying` turned out to be LITERALLY
  `buildPlayColOn[buildActiveFerry] ?? false` — the active ferry was already using the same on/off boolean as every
  background ferry, so the two gates unify with zero special-casing. Deleted `buildFlattenFerry` + the `playCol*`
  flattened-representation fields entirely, plus — found via a zero-caller trace, not guessed — a SELECT-page
  per-column I/O editor that was already dead behind a permanently-nil stub (its own comment had already flagged
  "returns with the Stage 3 unified ferry composer"), and the transitional `Snap.stagingRowBase` Stage 2 introduced
  (`Snap.rows` settles back to 32). **DELIBERATE BEHAVIOUR UNIFICATION, flagged not buried:** a machine-less cell was
  a silent "unset" on the staging grid but a passthrough live wire on the old flattened background path; onto one
  code path, one rule — kept the staging rule (silent) for every ferry, matching "no active/background distinction."
  DEVICE-AUDIBLE if a background ferry ever relied on that passthrough.
  **STAGE 4 — multi-select authoring, FEATURE COMPLETE (2026-09-27, `a71523d`; macOS 1126 green incl. 10 new, iOS
  builds; DEVICE eye/ear owed on the whole feature). `BuildPart` gains `stagingMulti` (a per-column 4-bit mask) +
  `selMulti`; `BuildSceneLogic.activeRungs(sel,multi,c)` is the plural sibling of `selectedRung` — the "POLY-PREP"
  seam a 2026-09-14 session set up for exactly this ("only these two bodies change — every caller already asks
  here"). `composeSceneMeta`'s per-ferry loop iterates every active rung instead of one; a ferry's own `selMulti`
  gates whether its mask is even consulted, so flipping back to SINGLE can't leave a stale mask sounding rows it
  shouldn't (a real fix, not automatic — required threading `selMulti` into the engine read, not just the UI).
  `partGridTap` gained a multi-aware toggle branch (XOR a row's bit rather than exclusive-overwrite); the lead
  (which row anchors the playhead/focus) follows the most recently toggled row, reassigning to a survivor if the
  lead itself is toggled off. UI: a SINGLE|MULTI `launchInline` in the ferry settings tab, same shape as CHOKE.
  Two v1 defaults from the plan, applied not re-litigated: the row-bulk-select rail REPLACES a column's active set
  rather than adding to it; the part-grid playhead sweep stays lead-row-only even in MULTI (a per-row sweep is a
  visual follow-up, not gated on anything audio). **Found in passing:** `buildPartGridDrag`'s row bound was still
  hardcoded to 8, a stale leftover from Stage 2's shrink to 4 (no observable bug — the touch coordinate space was
  already sized correctly — but wrong on its face, fixed); `buildFerryFlashIndices` + the emitter-strip playing-
  colour band both iterated the lead only, generalized to every active rung so a multi-row ferry's flash/tint
  doesn't under-represent what's actually sounding. Byte-identical for any ferry left in SINGLE (the default).
  **THE WHOLE ARC (Stages 1-4, one session):** replaced the old model — rows 0-7 shared by whichever ferry sat on
  the bench + a dead pre-ferry "PIECE" arrangement grid, rows 8-15 one mono row per background ferry via
  `buildFlattenFerry` — with 8 ferries × 4 dedicated engine rows each, always live, no active/background
  distinction, plus per-ferry SINGLE/MULTI row selection. Paul's own diagnosis ("why do we have rows 1 to 8 anyway
  — sounds like a byproduct of an older model") was confirmed exactly right: `buildPerformPart` had zero live
  writers, and the part-editing UI had already quietly shrunk to 4 rows (2026-09-08) without the engine following
  suit. Plan: a session-local plan file (not checked in) validated by a dedicated research pass before any code
  moved — closed two real open risks (a `col*8+row` UInt64 tap-mask cluster confirmed fully dead end-to-end; the
  `Snap.rows`/`Snap.cells` call-site audit across Router/Kernel/SnapshotBuilder found almost everything already
  symbolic, not hardcoded) before Stage 1 touched a single file. **DEVICE-OWED, the whole arc:** a backgrounded
  ferry with 2+ rows populated actually sounds both machines together; the SINGLE|MULTI toggle feel; no stuck notes
  across ferry activate/deactivate/mute while multi-row content plays in the background.**
- **▶ FERRY COLOUR SWAP — closes the "invents a third colour" gap (2026-09-27, on `main`, `1c2d3b7`; iOS
  builds, macOS 1123 green; DEVICE eye owed). Paul described the intended model for select→ferry colour (pick a
  colour via a selector → the SELECT cell shows it → dragging it onto a ferry lands verbatim, regardless of that
  ferry's own predetermined colour → a clash swaps the two slots' colours, never invents a new one → the SELECT
  cell and the ferry can never disagree) and confirmed it should ALSO hold when the clash is against an
  ALREADY-POPULATED ferry, not just an empty placeholder — the one case the 2026-09-12/13 ferry drag-and-drop work
  didn't cover (`buildPopulateFerry`'s "FERRY HUE UNIQUENESS" block fell back to `buildDistinctHue()` there,
  silently diverging from the SELECT cell that fed it — the exact class of bug the whole ferry-colour-review
  session flagged as still-open). FIX: `BuildSceneLogic.ferryColourDisplacement` dropped its `empty` filter — it
  now matches ANY other ferry currently wearing the incoming colour, populated or not; `buildPopulateFerry` applies
  the swap by recolouring the OTHER ferry's `.ferryHue` (+ mirroring into its own `machineHueOverride`, so its
  machine box can't fall out of step with its own ferry swatch) when populated, or its `ferryHueAlloc` placeholder
  when empty — `buildDistinctHue()` is never called on this path anymore, so the dropped cell's colour always lands
  verbatim at the target. Rewrote `testFerryColourDisplacement` to the new signature (no more `empty:` array) and
  flipped its last assertion (a populated clash is now chosen for the swap, not rejected). **RESIDUAL, flagged not
  fixed:** the DISPLACED ferry's colour change doesn't propagate to any SELECT-grid cell that may have committed
  with that OLD colour — there's no persisted link from a ferry back to whichever cell(s) seeded it (colour capture
  on SELECT is already one-shot-at-commit by design, per the 2026-09-12 model, not a live binding); closing that
  fully would need a new bond and is out of scope for this fix. Also NOT touched: the broader Refactor 2
  (`Docs/PLAN-ferry-colour-unification.md`) — one accessor across all ~12 hue-reading surfaces — which is a
  separate, larger, still-open decision.**
- **▶ CLOCK — GLIDE "elastic landing", in sync whether or not a step glides (2026-09-26, on `main`, on fix/clock-
  glide-sync; macOS 1120 green incl. fuzz, iOS builds; DEVICE ear owed). Paul: "when it lands on a target, whether
  it got there with or without glide, it should be in sync." Confirmed real: a plain linear GLIDE ramp only
  contributes its own AVERAGE of (from,to) over the column, strictly less than `to` when accelerating — so it
  banks LESS local time than SET reaching the same target, and that shortfall carries forward unchanged for the
  rest of the SPAN window (already provable via the existing `testClockDrawnGlideRowSoftensTheColumnTransition`).
  Asked Paul to pick a resolution (a monotone ramp can't avoid the shortfall — a calculus fact, not a bug); he
  picked **elastic landing**: `clockDrawnGlideShape` splits a glide column into two straight-rate segments — a
  short "kick" from `from` toward a computed peak `P`, then a longer ease from `P` back onto `to` — chosen so the
  TWO SEGMENTS' combined area always equals `to × rateBeats` exactly, same as SET. `P = to + f×(to−from)`; f
  defaults to a symmetric 0.5 for any accelerating (or mild decelerating) glide, shrinking (5% floor) only for a
  STEEP deceleration where a full-size overshoot would otherwise drive `P` negative (local time running backward —
  the exact class of bug WAVE's old depth clamp existed to prevent; no ladder rung pair near that floor in
  practice, only extreme multi-rung jumps like ×4→÷4 engage it). `clockDrawnColumnAdvance` (new, replaces 3
  copy-pasted closures) now returns `to × rateBeats` for a GLIDE column too — the fix itself, shared by
  `clockDrawnPhase`, its inverse, and `clockDrawnDriftPerLap` so they can't disagree; the drift readout now only
  ever reports a lane genuinely authored to run fast/slow on average, never an artefact of glide-vs-SET choice.
  **BUG CAUGHT MID-BUILD:** a first draft generalised `P` for the adaptive-f case but left the within-column
  quadratic denominators hard-coded to `/T` (only correct when f is exactly 0.5) — `testClockDrawnPhaseInverse-
  RoundTrips` failed on the extreme ×4→÷4 all-glide case; traced with a throwaway Swift script rather than
  re-guessing by hand (this session's own standing rule), fixed to `/(2×half)`/`/(2×rest)`. Rewrote the 4 affected
  DerivationsTests with fresh values pulled from the actual function (never re-hand-derived blind) + added
  `testClockDrawnGlideFullColumnAlwaysMatchesSetAtTheSameTarget` (sweeps the whole 9-rung ratio ladder both ways —
  81 pairs — asserting zero drift AND a never-negative peak) as the standing regression guard. 1120 macOS tests
  green incl. all 8 fuzz scenarios; RouterTests' existing glide-softening test still holds (GLIDE is still visibly
  later than SET WITHIN the ramp, converging to exactly the same phase once it lands). **NEXT:** device ear-check —
  confirm a glide into a target no longer leaves the rest of the pattern audibly later than a same-target SET would.**
- **▶ CLOCK — GLIDE "elastic landing" NARROWED to accelerating glides only (2026-09-27, on `main`, on fix/clock-
  glide-decel-safe; macOS 1122 green incl. fuzz, iOS builds; DEVICE ear owed). SUPERSEDES the entry above the same
  day it landed — Paul actually tried it and reported two device symptoms: "weird behaviour… appears to change the
  velocity two cells after a jump to another tempo when glide is set on the jump only," and "hiccups… a stutter"
  with columns 1–4 all SET+glide to ×1 (column 8 at ×2, so the whole run decelerates ×2→×1 across 4 columns via the
  SPAN-coalescing rule). Traced BOTH with a throwaway script rather than guessing: for a DECELERATING glide (e.g.
  ×2→×1), the elastic curve's cumulative local time runs UP TO 16% AHEAD of a same-target SET for most of the
  column before snapping back to exact parity only at the very end — the mechanism is a hard calculus asymmetry, not
  a tuning knob: an ACCELERATING glide's elastic curve can be PROVEN to stay ≤ a same-target SET throughout the
  whole column (verified both analytically and by sweep-testing the full ratio ladder), so it can never make a
  downstream driver/fold-consumer discover an early/extra tick — but a DECELERATING glide's zero-drift correction
  necessarily requires the opposite: dipping BELOW the (slower) target first, which means racing AHEAD of a
  same-target SET before catching back down. That "ahead of schedule, then catch down" motion is exactly what reads
  as a stutter, and it compounds badly across the coalesced 4-column run (four such wobbles in series). **FIX:**
  `clockDrawnGlideAdvance`/`FullAdvance`/`AdvanceInverse` now branch on `to >= from` — ACCELERATING keeps the full
  elastic "in sync" treatment (now with NO adaptive-f floor needed at all, since `P = to + 0.5×(to−from) ≥ to > 0`
  unconditionally when accelerating — the floor only ever existed to protect decelerating overshoots, which no
  longer take this branch); DECELERATING falls back to the plain single straight-line ramp — this feature's
  ORIGINAL shape, honest/non-zero-average, exactly what shipped before the "in sync" work began. Re-verified with
  the same throwaway-script technique: the 4-column ×2→×1 span now shows a PERFECTLY MONOTONIC, smoothly
  decreasing rate in every column (no dip-then-recover) — confirmed against the actual function's own numeric
  output, not re-derived by hand. **`clockDrawnGlideShape` simplified** (the adaptive split-fraction tuple is gone —
  always exactly `T/2` now, so it returns a scalar peak, not a tuple) — a direct consequence of decel no longer
  needing it. **TESTS:** rewrote `testClockDrawnGlideFullColumnAlwaysMatchesSetAtTheSameTarget` (accel → matches
  SET exactly; decel → the honest average, an explicit different expectation) + `testClockDrawnGlideOfDifferingTargetsIsUnaffectedBySpanLogic`
  (mixes an accelerating run with a trailing decelerating column — GLIDE now agrees with SET through the
  acceleration and explicitly diverges at the deceleration, asserted both ways) + added
  `testClockDrawnAcceleratingGlideNeverRunsAheadOfSet` (sweeps the whole ladder × a beat range, the standing
  regression guard for the safety property the whole fix rests on). 1122 macOS tests green incl. fuzz; the two
  pre-existing RouterTests (`…SetAndGlideProduceDifferentFoldResults` on a DECEL [×4,×1] pair, `…SoftensTheColumn
  Transition` on an ACCEL [×1,×4] pair) both still pass unchanged, confirming each already happened to sit on the
  side of this asymmetry it needed to. **HONEST REMAINING GAP (flagged, not a bug):** decelerating glides are back
  to the ORIGINAL "not perfectly in sync" behaviour Paul first complained about — eliminating that drift there is
  mathematically impossible without reintroducing the exact overshoot artefact just removed (proven, not a
  limitation of this implementation specifically). The `clockDrawnDriftPerLap` readout still exists precisely for
  this case. **NEXT:** device ear-check on both fronts — confirm the 4-column decel run now feels like one smooth
  slowdown (no stutter), and confirm an ACCELERATING jump still lands cleanly in sync as before.**
- **▶ KILL STEP — a new TIME processor, sibling to CLOCK (2026-09-26, on `main`, `b1e7a19`; macOS 1121 green, iOS
  builds; DEVICE ear/eye owed). A row of ON/OFF steps (variable count, default 8) + its own RATE + SPAN: a disabled
  step is skipped, everything downstream jumps past it, enabled steps repeat to fill the pass (4-of-8 → the first
  half plays twice; 3-of-8 → a 3-cycle rotates against the bar) — `lapColumn`'s ephemeral LAP algorithm, AUTHORED
  per-cell. Reached the WHOLE generator roster CLOCK's own widening earned this session FOR FREE, by generalizing
  the three functions that type-check `.clock` (`Router.driverClockBeat`/…Inverse/`clockTransformedBeat`) to also
  detect `.killStep` — no new call sites; composes with CLOCK too. New pure `killStepPhase`/`Inverse`: a DISCRETE
  remap (real gaps in local time, unlike CLOCK's continuous warp) — monotonic in the real column count so the
  shared tick-search machinery still works; all-disabled falls back to all-enabled; a beat landing in a gap snaps
  FORWARD to the next enabled repeat. Model additive-Optional (`killStepCount`/`Enabled`/`Rate`/`SpanN`); UI =
  STEPS + a `toggleLane` row + an ArpRate seg + `frameSpan`; self-names "N/total". Tested (Derivations + Router,
  mirroring the CLOCK+DEST tests) + fuzz roster. **NEXT:** device ear/eye pass.**
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
- **Older entries (2026-09-01 and before) archived to `Docs/status-log-archive.md`** — moved out
  2026-09-26 to keep this file inside the context char limit; nothing was deleted, just relocated.
  Read that file for build history predating the entries above; `Docs/pending-tasks.md` stays the
  forward checklist.

## Style
- Swift, no external deps beyond apple/swift-atomics (SPM, already in project.yml).
- Comments cite spec sections (e.g. `// §3.2: stepped fields quantize`). Keep doing this —
  the spec is the contract, and drift between code and spec is the project's main risk.

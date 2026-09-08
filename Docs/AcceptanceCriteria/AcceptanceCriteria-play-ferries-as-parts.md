# Acceptance Criteria — THE PLAY FERRIES ARE PARTS

Status: **RATIFIED (design, Paul 2026-09-08)** · engine substrate reuses the existing flatten/play-layer path ·
UI + model refactor, device-owed. This supersedes the "play ferry = a play-layer cell (SELECT-backed or part-backed,
multi-step passes hand-authored)" model for the rooms workbench.

## The one idea
Each of the **8 play ferries IS a part** — a full part-grid instance. The ferry row is the navigation: selecting a
ferry shows/edits/plays its part; an empty ferry shows the SELECT grid. Up to **8 parts play at once**. Going forward
there is **no part/select toggle** — the ferries are how you move between parts and the browser.

## Model of record
- A **part** = the existing `BuildPart` (BuildModel.swift): `stagingCells`/`stagingSel` (the 4-row × up-to-16-col grid +
  the per-column selected rung), `rowChain`/`rowUnder`/`cast`/`castSlots`/`selID`, `receiver`/`emitters` +
  `rowReceiver`/`rowEmitters` (per-row I/O), `rate`, `length`, `deployed`. Unchanged — this is already "a part."
- The play grid becomes **8 part slots**: `parts: [BuildPart?]` (one per ferry column 0–7). This collapses the current
  per-cell `buildPlayCellPart: [[BuildPart?]]` (8×8) to per-ferry (8). `nil` = an empty ferry.
- A ferry is a **live view** of its part: editing the bench (part grid) while ferry `t` is active mutates `parts[t]`
  directly. No copy/commit round-trip.
- **Persistence:** the 8 parts travel with the document. `BuildPlayGridData` already carries `playCellPart` +
  `workingPart` + the referenced ephemeral colours (`colours`/`hues`/`idCounter`); the 8-slot `parts` array replaces the
  8×8 `playCellPart` there (with a decode-tolerant migration — see Phase 1).

## Playback — a real STEP SEQUENCER (active via staging) + flatten for the background (NO engine change)
Ratified refinement (Paul 2026-09-08): the flatten-to-a-single-hidden-row model is NOT how the part you're looking at
should play — it must sequence like a step sequencer (visible sweep, per-column rung, live selection response). So:
- **The ACTIVE (on-bench) ferry plays via the STAGING sequencer** (`buildVoiceOwner == .part` → `composeScene`'s
  staging block, rows 0–7): the part grid SWEEPS, each column fires its SELECTED rung, and editing the selection/cells
  responds live (staging composes the live bench every publish). This is the visible step sequencer + `roomsPartPlayhead`.
- **BACKGROUND (non-active) "on" ferries play via the flatten** onto the hidden play-layer rows (8–15): a mono line
  (selected rung per column) at the part's `rate`/`length`, per-step I/O carried. They don't need a visible sweep.
- **Simultaneity:** one staging voice (the active) + up to seven play-layer lines = up to 8 parts at once. Switching
  ferries hands the staging voice to the newcomer and pushes the outgoing (if still on) to a play-layer line.
- A part is a **mono line** (selected rung per column); poly is future. Multi-step "passes" survive ONLY as the
  background flatten's internal representation — never hand-authored.
- **Poly per part is explicitly FUTURE, not now** (Paul 2026-09-08). It would need more play-layer rows than the 8
  slots allow (8 parts × up to 4 rows), i.e. a real engine change — out of scope here.

## Behaviour (Given / When / Then)
- **G** a ferry holds a part · **W** the user taps ferry `t` · **T** the bench shows `parts[t]`'s grid (view/edit); the
  part plays via the flatten path if it is "on"; the ferry reads **selected**.
- **G** an **empty** ferry · **W** the user taps it · **T** the bench shows the **SELECT grid** (browse/build a chain).
- **G** the SELECT grid with a machine/MIDI **chain** selected · **W** the user **long-presses an empty ferry** · **T**
  a **new part** is created in that ferry, seeded with the selected chain in **row 0**; the ferry becomes selected and
  its (new) part grid opens. (A ferry always holds a part, even when seeded from a single chain.)
- **G** several ferries "on" · **W** playing · **T** all their parts sound simultaneously (up to 8 lines).
- **G** the user edits the bench while ferry `t` is active · **T** the edit writes back to `parts[t]` (live view).
- **"Both ferry buttons show as selected"** (Paul's phrase) resolves to: the active ferry reads selected on the ferry
  row, and — while its part is the bench — the bench's own ferry/echo of that column reads selected too. (Confirm the
  exact two lit elements on device; it's a display detail, not a model fork.)

## What RETIRES
- **SELECT-backed play cells** — a ferry is always a part now (`roomsAssignPlayColumn`'s single-cell path folds into
  "seed a new part from the chain").
- **Hand-authored multi-step passes** — passes stay as internal flatten output, not a user-facing authoring step
  (`roomsFlattenPartToPlay` becomes an internal "flatten `parts[t]` for playback" helper).
- **The part/select toggle** — replaced by ferry selection (empty → select, populated → that part). *(Phase 3.)*
- The per-cell `buildPlayCellPart` 8×8 store + the per-row play cells (`buildPlayCells`) collapse to the 8-slot `parts`.

## What STAYS (unchanged)
- The engine + the play-layer flatten path + `buildPlayColOn` (which ferries are on) + per-step I/O.
- `BuildPart` itself, and the bench part-grid editor (the 4-row grid + rung selection + rails + footer).
- The velocity/processor work, catalog, etc. — untouched.

## Open display detail (not a model fork)
- Exactly which two elements light for "both selected," and whether an "on" ferry that is NOT the currently-viewed
  part shows a distinct "playing-but-not-viewed" state. Decide on device.

## Implementation plan (phased, each device-verifiable)
**Phase 1 — model + persistence (no visible change).**
- Add `parts: [BuildPart?]` (8) as the play-grid model; back it by `BuildPlayGridData.parts` (additive-Optional;
  decode-tolerant `init(from:)`; migrate an old doc's `playCellPart`/`colSteps` → seed `parts` from the per-column
  part-backing where present). Keep the flatten fields (`colOn`/`colSteps`/`colLen`/`colRate`/`colStepRecv/Emit`) as
  derived playback state. Round-trip test + migration test (macOS suite).

**Phase 2 — ferry nav + seed-from-select + live edit-write-back.**
- Tapping ferry `t`: populated → load `parts[t]` onto the bench (`buildLoadPart`-style) and mark it active; empty →
  show the SELECT grid. Long-press an empty ferry on SELECT → `buildSeedPartFromChain(t)` (new part, chain in row 0),
  activate it. Bench edits write back to `parts[buildActiveFerry]`. Selecting reads "on" ferries and flattens each for
  simultaneous playback (reuse the existing flatten). Device-verify: seed, switch, simultaneous play, edit persists.

**Phase 3 — retire the toggle + SELECT-backed cells + hand-authored passes.**
- Remove the part/select toggle; the ferry row drives the view. Fold `roomsAssignPlayColumn`'s single-cell path into
  seed-a-part. Delete the per-cell `buildPlayCellPart` 8×8 + per-row `buildPlayCells` once `parts[8]` is the source of
  truth. Tidy dead state. Device-verify the whole nav has no toggle and nothing regressed.

## Notes
- Ferries are fixed at **8** (matches the 8 play-layer engine rows).
- Behaviour change ⇒ this spec is the contract; reconcile code + tests to it, then device-verify each phase.

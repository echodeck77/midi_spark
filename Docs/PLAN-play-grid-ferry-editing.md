# PLAN — Play-grid ferry editing (parts round-trip through the part grid)

_Design settled with Paul 2026-09-05. Nothing built yet. Status: DRAFT plan, uncommitted (the other instance is live)._

## The idea in one paragraph

The **part grid is a single edit buffer**. Each of the play grid's **64 cells (8×8) is a stored part**. There is one
extra **persistent "working part" (the 65th)** holding un-ferried WIP — the part grid's "home". **Flatten** snapshots the
*whole* part into a play cell (lossless), so **unpack** (touch the cell's bottom ferry) loads it straight back into the
part grid for editing. Unpacking **removes the cell from the play grid** and **live-links** it — the column keeps playing,
now driven live from the part grid — and **push** re-deposits the edited part onto the grid. A cell ferried from the
SELECT grid stores no full part, so unpacking it **clears the part grid to just that one cell**. WIP is never lost: the
working part is parked on unpack and returns home.

## The model (target)

- **Play grid = 8×8 = 64 cells.** (Already true — `BuildPlayGridData.cells: [[String?]]` is 8 cols × 8 rows.) Each cell
  is upgraded from "a colourID (one chain)" to **optionally a full `BuildPart`** (part-backed) OR a colourID
  (select-backed). Part-backed ⇔ `playCellPart[c][r] != nil`; select-backed ⇔ nil part + the existing colourID.
- **The ferry (8, one per column) = a live POINTER** to that column's **selected** cell (`cells[c][sel[c]]`), always
  reflecting it. Touch → navigate to the part grid + **unpack** that cell.
- **The working part (65th, persistent)** = the part grid's home buffer for un-ferried WIP. Maps onto the existing
  `buildUnassigned` concept (WIP not yet on the play grid), promoted to always-present.
- **The live-link** = which one play cell the part grid currently drives (`liveLinkCell: (c,r)?`, or none). At most ONE
  at a time. While live-linked, that column's playback composes from the part grid; on push/leave it reverts to the
  stored part.
- **Per-cell source** = part-backed vs select-backed (drives the unpack behaviour). Implicit from `playCellPart != nil`.
- **A cell's playing form is DERIVED from its stored part** (flatten-on-store) — "two views of one thing". The part is
  the source of truth; the pass/continuous-voice the render uses is recomputed whenever the part is (re)stored.

### Naming (Paul flagged it — settle before Stage 3)
Today: `BuildPart` = the authoring-grid contents; `buildParts` = the deployed-parts array; a play cell = a colourID.
Target: **a play cell IS a part.** So `buildParts` (the deployed array) folds INTO the 64-cell store, and "the working
part" is the un-deployed home. Proposed vocabulary: **PART = a play-grid piece (64 of them) + the WORKING part (1)**;
the part grid = "the bench". Decide the words at Stage 3; keep the type name `BuildPart`.

## Settled behaviour (Paul, 2026-09-05)

- Geometry: 8×8; one ferry per column pointing at the column's selected cell. ✓
- A play cell carries both what it plays AND the part it unpacks to. ✓
- Unpack **removes the cell from the play grid** (checked out); it keeps playing, live from the part grid. ✓
- Only ONE cell live-linked at a time. ✓ (to confirm at build)
- Select-backed cell → unpack clears the part grid except that one cell. ✓
- The working part always exists; a select-push must not clobber it. ✓

## The home-return trigger — RESOLVED: restore-WIP-on-push (Paul 2026-09-05)

**Push re-deposits + reloads the WIP.** When you push the bench back to the play grid: (1) the edited part is
re-deposited onto the target play cell and plays there (its ferry is now its source); (2) the parked **working part
(WIP) reloads onto the bench in a STOPPED state**. So you "stay on the bench" (now showing the WIP, stopped) while the
thing you pushed lives on the play ferry. The WIP is never lost. (Earlier I'd mislabeled this "(A) rug-pull" — for Paul
it's the point: the WIP coming back is exactly what's wanted, and the pushed part is safely on the grid.)

## Staged build (each stage builds + verifies before the next)

**Stage 1 — MODEL (pure, off-device testable). Additive, byte-identical for old docs.**
- Add `playCellPart: [[BuildPart?]]` (8×8) to the play-grid store + `BuildPlayGridData` (decode-tolerant Optional).
- Promote the working part to a persistent, always-present `BuildPart` (reuse/rename `buildUnassigned` as home).
- Add `liveLinkCell` + the source-flag accessor (part-backed ⇔ part != nil).
- Pure helpers (BuildSceneLogic, in the test target): `flattenToPlayCell(buffer) -> (part, playingForm)`;
  `unpack(cell) -> BuildPart` (part-backed = the stored part; select-backed = a one-cell part = clear-except-this-cell);
  `parkWorking` / `restoreWorking`.
- Migration: an old doc's play grid (colourID cells + `colSteps` passes) keeps working unchanged (part = nil everywhere);
  only NEW flattens populate `playCellPart`. Byte-identical.
- **Tests:** flatten→unpack is a lossless round-trip (part-backed); select-cell unpack yields a one-cell part; the
  working part survives an unpack/push cycle; old-doc decode = nil parts, unchanged behaviour.

**Stage 2 — FLATTEN STORES THE WHOLE PART (logic).**
- Rework `roomsFlattenPartToPlay(t)` to snapshot the current `BuildPart` into the target cell (part-backed) AND derive
  the playing form. The derived playing form must equal today's pass (so playback is unchanged) — only the source part
  is now retained. The SELECT ferry stays select-backed (part = nil).
- **Tests:** after flatten the cell holds the full part; the derived playing form == the pre-change pass (regression).

**Stage 3 — THE BOTTOM FERRY, REWRITTEN (UI, device-owed).**
- Rebuild `roomsPlayFerry` from the ground up: each ferry is a live pointer to `cells[c][sel[c]]`, reflecting the
  selected cell (hue/label/part-or-chain glyph), updating as the selection cursor moves.
- Touch → navigate to the PART grid + unpack (Stage 4). Settle the naming here.

**Stage 4 — UNPACK / LIVE-LINK / RE-DEPOSIT (UI + engine, device-owed).**
- Unpack: **vacate** the cell on the play grid; park the working part; load the cell's part into the bench; set
  `liveLinkCell`; keep the column sounding, now composed live from the bench.
- Push (flatten back to a ferry): store the edited part to the target cell (re-deposit + it plays there), derive its
  playing form, clear the live-link, then **reload the parked WIP working part onto the bench in a STOPPED state**
  (restore-WIP-on-push — resolved).
- **Nested unpack — RESOLVED (Paul 2026-09-05):** unpacking always rolls the CURRENT bench part into the WORKING slot,
  then loads the new cell. So unpack A (bench = A, WIP ← old bench) → unpack B (bench = B, **WIP ← A**). Single-depth:
  the immediately-previous bench part is preserved as the working part; a push reloads it. (Deeper history isn't kept —
  by design.)
- Select-backed path: unpack clears the bench except the one cell; push re-deposits.
- **Device-owed:** the whole navigation + live-link feel; that the still-playing column hands off cleanly bench→stored
  (no stuck notes at the hand-off — reuse the existing boundary-close machinery).

**Stage 5 — PERSISTENCE + CONSOLIDATION.**
- Persist up to 65 full parts (the 64 `playCellPart` + the working part) in the document (extends `BuildPlayGridData` /
  `buildUnassigned` encode). Decode-tolerant.
- Fold the legacy `buildParts` deployed-array + `buildPerformPart` mapping into the per-cell store (careful — they thread
  performRate/Len; do this only once the new store is proven). Migration keeps old docs loading.

## Risks / watch-list
- **Stuck notes at the live-link hand-off** (bench→stored on push, and stored→bench on unpack) — must route through the
  existing column-boundary close (invariant 4).
- **The `buildParts`/`buildPerformPart` fold (Stage 5)** is the load-bearing/risky part — it's threaded into per-part
  clock (rate/length) and the perform mapping. Stage it last, additive-first.
- **Two-instance git hazard** — the play grid lives in BuildPage/BuildModel, which the other instance also edits. Land
  each stage when the tree is quiet; model/tests (Stages 1–2) are lower-collision than the BuildPage UI (Stages 3–4).

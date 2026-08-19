# Acceptance Criteria — THE PER-PART CLOCK (independent tempo + length + playhead)

Status: **spec of record** (Paul 2026-08-19). Supersedes the one-scene / one-clock assumption for the BUILD play grid.
BUILD is becoming the only surface (GRID/PROCESSORS retire), so this replaces the global `stepRate`, not augments it.

## The idea
A **part is a track.** Each part owns its **rate** (step width) and its **length** (columns; 8 today, `< 8` a future
"promote only looped columns" step) and thus loops on **its own clock**. Deploying two parts to the play grid at
different rates plays them **at different tempos simultaneously** — a long sequence next to a short one. Each part draws
**its own playhead** (rendered per row, since parts may span a dynamic number of rungs going forward).

## The load-bearing invariant is PRESERVED
The spec's real rule is **"derived, never accumulated"** (CLAUDE.md architecture invariant 2): the playhead/phase are
pure functions of the host beat. That survives exactly. Each row's playhead is `(hostBeat / rowStep) mod (rowLen·rowStep)`
— **N derivations from the one host beat**, phase-locked to the transport, striding against each other by their rates.
So there is no free-running accumulation; the "one clock" generalises to "one clock **per row**, all host-derived,"
which is why the off-device fuzz can still prove it (below).

## The seam — per-ROW clock in `Router.process()`
Today `process()` derives ONE `S = box.stepBeats`, ONE `effColumn`/`pass`/`cycleBeats`, does ONE column-transition
flush (`closeExceptLegatoHolds`), and runs `emitColumnHolds` + the tick row-loop at that single column. The generalisation
keeps every GLOBAL edge (transport start/stop, panic, scene-flush, latch-edge, echo drain, MOD/GLIDE, the empty-pool
guard) and makes the **column derivation + transition + holds + ticks PER ROW**:

For each row `r`:
- `Sr = box.rowStepBeats[r]`, `Lr = box.rowLen[r]`, `cycleR = Lr·Sr`.
- `mNowR = musicalOf(beatPos, Sr, a)`; `absStepR = ⌊mNowR/Sr⌋`; `trueColR = ⌊(mNowR mod cycleR)/Sr⌋` (0…Lr−1).
- `effColR = lapColumn(heldColumns, absStepR, trueColR)`; `forceColumn` overrides (PLAY: THIS CELL).
- **Per-row column transition:** track `prevEffColumnRow[r]`; on change, close ONLY row `r`'s sounding voices at the
  boundary **except its legato holds** (voices carry `cellIndex = col·8+row` → filter by row), reset row `r`'s tick
  dedup (`lastTick[r]`, `strumProgress[r]`, `lastGenStep[r]`), then re-hold row `r` at `effColR`.
- Emit row `r`'s holds + ticks at `effColR` with `Sr`/`cycleR` (the emit fns already take `S:`/`effColumn:`/`cycleBeats:`).

Echo/MOD/GLIDE already iterate a column's cells; they run per row at `effColR` with `Sr`. `diag.effColumn`/`diag.pass`
stay the ROW-0 representative for the header readout; the per-row playhead reads `box.rowStepBeats`/`rowLen` directly in
the UI (host-derived, same as today's sweep).

## Compatibility — DEFAULT is byte-identical
`rowStepBeats[r]` defaults to the global `stepBeats` and `rowLen[r]` to `Snap.cols` (8) for every row. With all rows
equal, every per-row derivation collapses to today's single-clock values and the emitted byte stream is unchanged —
locked by a test (`testUniformPerRowClockMatchesGlobal`) and by the whole existing RouterTests suite staying green.

## Model
- `BuildPart` gains `rate: StepRate` (default = scene default) and `length: Int = 8` (1…8; `< 8` reserved for the
  looped-columns future). Additive-Optional on the persisted `BuildPart`.
- `SceneState` gains per-row overrides `rowStepRate: [StepRate?]?` and `rowLen: [Int?]?` (nil ⇒ the scene default) —
  additive-Optional, old docs decode nil ⇒ uniform.
- `SnapshotBox` carries `rowStepBeats: [Double]` (8) + `rowLen: [Int]` (8); `SnapshotBuilder` resolves them per row.
- `BuildSceneLogic.composeScene` sets each play-grid row's `rowStepRate`/`rowLen` from its part (`performPart[r]`), and
  the staging (current-part audition) rows from the current part. The chain-audition row uses the selected part's rate.

## UI
- The rate control leaves the header and lives at BUILD's **bottom-left** (by the reel glyph), editing the **current
  part's** rate. Swing stays a global header control (a groove feel; per-part swing is a later option).
- **Per-part playheads:** each play-grid row (and the part grid) draws its own sweep on its own clock; a part spanning
  several rows shows one sweep per row (aligned, since they share the part's clock). Rendered per row so dynamic
  rung-counts per part "just work."

## No stuck notes — the contract the fuzz enforces
`FuzzTests` randomises `rowStepBeats`/`rowLen` per row (incl. coprime rates → polymeter, and short `Lr`) and asserts,
across every transport/seek/tempo/snapshot-swap edge, the existing invariants: **no key sounding after a flush**,
`Router.quiescent` after settle, determinism (same seed ⇒ byte-identical), and I5 in-range. The per-row column
transition is the one new stuck-note surface — the boundary close is scoped by `cellIndex` row so a slow part's held
note is never truncated by a fast part's boundary.

## Staging (each stage independently green + committed)
- **A — model foundation (non-breaking):** the model + box fields + builder + composeScene wiring, all defaulted → the
  uniform-equals-global test. No engine change.
- **B — the multi-clock engine:** the per-row derivation/transition/holds/ticks in `process()`; `emitColumnHolds` +
  the boundary close refactored to per-row; the fuzz extended. The careful stage.
- **C — UI:** the bottom-left per-part rate control + per-part playheads.
- **D — later (not this pass):** length `< 8` (the part loops over `Lr` columns) once B is proven.

## Deferred / out of scope here
Per-part swing · variable rung counts as a data model (the grid stays 8 rows; `Lr` is a loop length, not a row count) ·
the retirement of the GRID/PROCESSORS scene machinery (fades as BUILD subsumes it) · saving per-part clocks with the
scene document (folds into the existing BUILD persistence).

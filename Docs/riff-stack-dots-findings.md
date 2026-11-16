# RIFF GRID STACK DOTS — findings (§11), before editing

**Ferry:** display-only. Each sounding stack note → a small grey dot on the riff grid, in the
cell of (its lane's riff column at the **start** hit, the rank the stack played). Dot: 3 pt,
`stackRankColour(rank)`, a 0.5 pt #0D0F14@70 % ring, top-right corner **above** the cell's arrow,
right-to-left in lane order, a 160 ms ease-out fade on note-off (tunable to 0 = hard cut), no dots
when stopped / muted / PLAY-STACK-off. **Golden byte-identical by construction** — no engine,
snapshot or note-feed change.

> ⚠ **Spec file lost.** `claude/ferry-riff-stack-dots.md` is not on disk (not tracked, not
> untracked, not in either worktree). These findings and the build follow the spec as captured in
> the working context (§0, §1.2, §1.6, §2–§5, §11). If a sub-section's exact wording matters below,
> re-share the spec — flagged per the "name possible mismatches" rule.

## §0 GATE — the grey ramp is ALREADY BUILT (do NOT rebuild it)
The spec says "if the grey stack-ranks ferry hasn't been built yet, this one builds that colour
ramp first." It HAS been built:
- `stackRankColour(rank:) -> EuclideousRGB` — `Fourfold/Engine/LaneStripBands.swift:202`
- `StackRankPalette.colour(rank:) -> Color` — `Fourfold/UI/RiffMapPalette.swift:22`

⇒ this ferry does **not** touch the ramp; the dot fill is `StackRankPalette.colour(rank:)`.

## The crux (§11.1) — how a stack note's starting hit and its column are found

**The note feed carries NO column.** `NoteRollNote` (`Fourfold/Engine/NoteRollRing.swift:81`) =
`onBeat, endBeat?, pitch, velocity, outs, rank` — and `NoteRollRecord` likewise. So the dot's
**column must be derived**, not read from the feed, and the spec forbids an engine/feed change
(no column may be stamped in the Router). The derivation reuses the lane strip's own mapping — this
is exactly what §1.6 ("the dots read the same held sets as the lane strip's stack outlines") asks
for:

1. **onset → step.** `laneStripSounding(...)` (`LaneStripBands.swift:334`) walks each held stack
   note and maps its `onBeat` → `stepOf(onBeat)` → **snapped to the nearest authored hit step**
   (`laneStripSnapToHitStep`, `:327`) → `stackOutline[step]` = the stack ranks sounding *now* at
   each step. `stepOf` is `{ b in euclideousStripNoteStep(raw: cometRawAt(b), n:, dir:) }` — the
   SAME sweep that places the playhead, so a dot can never disagree with the engine (this is §4.6
   "a note enters the set of the hit cell where it started").
2. **step → riff column.** The strip plan's per-hit column: `EuclideousStripHit.column`
   (`Derivations.swift:9769`, "the footer's riff column for this hit, **1-based**"), built by
   `euclideousStripHits` (`:9802`) from the footers' walk states. The hits are
   `plan.legs[stripLeg].hits` (one per step), `stripLeg = plan.legIndex(raw: cometRaw)`
   (`EuclidLaneUI.swift:442`).
3. **column → cell.** `EuclideousRiffPanelLayout.cellFrame(column:rank:)` (`Derivations.swift:5113`)
   — **column 0-based**, rank 1…8 (rank 8 is the top row). `EuclideousStripHit.column` is 1-based;
   `EuclideousArrowCell.column` (fed straight to `cellFrame` at `EuclideousPage.swift:7646`) is
   0-based ⇒ convert `col0 = column − 1`, the same 1→0 pattern `scrubRiffMarks` uses
   (`riffColumnHold − 1`, `:7674`).

So the per-lane dot set = `{ (col0 = hits[step].column − 1, rank) : for each step, for each rank in
stackOutline[step] }`, placed at `layout.cellFrame(column: col0, rank: rank)`.

## §4 fade (the one deviation from `laneStripSounding`)
`laneStripSounding` drops a note the instant it stops (`euclideousMixNoteSounds(n, at:)`,
`MixPanel.swift:305` = `onBeat ≤ now && (endBeat.map { $0 > now } ?? true)`). The 160 ms note-off
fade needs a slightly WIDER window: a note is still drawn (fading) while
`endBeat != nil && endBeat ≤ now && (now − endBeat)·secPerBeat ≤ fadeSeconds`. `endBeat` gives the
off time; the page `clock` tempo converts beats→seconds — **stateless**, no stored fade timer
(matches the "derived, never accumulated" invariant). ⇒ the dots need their OWN thin pure function
`euclideousRiffStackDots(...)`, not a raw reuse of `stackOutline`, because `stackOutline` has no
fade tail and no column. The function still CALLS the same onset→step→column machinery.

## §2.5 dot-vs-arrow placement
The riff-grid arrow sits in the cell's **centre** (`EuclideousArrowView` offset to
`cf.midX − size/2, cf.midY − size/2`, `EuclideousPage.swift:7654`; the STACK-grid variant is 23×17
at leftInset 3, vertically centred — `EuclideousStackArrowTuning`, `StackGrid.swift:85`). Placing
the dot in the cell's **top-right corner** (§2–3) clears the centre arrow — no overlap; the §2.5
gap is satisfied by corner placement. Right-to-left in lane order = lane 1's dot rightmost, then
lanes 2–4 stepping left, so several lanes' dots in one cell don't stack on each other.

## §5 states — no dots when stopped / muted / PLAY-STACK-off
- **stopped:** `riffPanelOverlay`'s `TimelineView(paused: !pulseLive)` already freezes
  (`EuclideousPage.swift:7634`); the feed's held notes also clear on a transport edge. The dot set
  is empty when not `pulseLive`.
- **PLAY-STACK-off:** the lane's stack part off = `euclideousMixLayerIsOff(line, notes: true)` /
  `notesOn`-resolved; drop the lane.
- **muted / solo-silenced:** `euclideousLaneIsDimmed` / `soloSilenced(idx)` — drop the lane (the
  arrows already suppress/dim the same way). The feed's `outs != 0` already excludes notes routed
  nowhere.

## §1 / finding-6 — where the derivation runs (architecture)
`cometRawAt` (the sweep) is built locally in the comet-bar Canvas (`EuclidLaneUI.swift:413`) from
`euclideousLaneCometChainRaw` / `euclidCometRaw` (pure engine fns) + the lane's
`n, dir, sub, chains, spanBeats, fillLine`. The riff-grid overlay is a sibling surface that does
NOT hold a strip plan today.

**Chosen approach (honours "share ONE clock — never let a widget re-derive its own"):** build the
per-lane inputs — `plan = laneStripPlan(lane, phaseLines[lane])` and a `cometRawAt` closure that
calls the SAME `euclideousLaneCometChainRaw`/`euclidCometRaw` the comet bar calls — once at page
body evaluation (like `arrowsNow`/`playedNow` are snapshotted at `:7296`/`:7385`); inside
`riffPanelOverlay`'s existing 60 fps `TimelineView`, evaluate the pure
`euclideousRiffStackDots(...)` at the live beat (so the fade is smooth and new note-ons appear). No
new clock is invented; the step→column mapping is the strip's own `laneStripSounding` +
`EuclideousStripHit.column`. Per-frame cost: 4 × `laneStripSounding` (cheap — one pass over the
held sets); the heavier `laneStripPlan` + the sweep closure are built once per body eval.

*Alternative rejected:* re-deriving the walk column at each note's onset beat directly in the
overlay (would duplicate the sweep clock — the project's named recurring bug class).

## Build order (each slice green, land at the end)
1. **These findings** (this doc) — before any edit.
2. Pure `euclideousRiffStackDots(stackHeld:hits:stepOf:hitSteps:now:fadeSeconds:secPerBeat:)` →
   `[EuclideousRiffStackDot]` (lane-agnostic; the page passes the lane) + tests (§1).
3. The dots view in `riffPanelOverlay` + the body-eval snapshot of per-lane inputs (§2–§3).
4. The 160 ms fade (§4) — the opacity curve in the pure fn, a `RiffStackDotTuning` enum for the
   3 pt / ring / 160 ms / corner-inset tunables.
5. States (§5) + docs + land.

## Verification
- `run.sh --golden` byte-identical (no engine change) — a sanity check, not expected to move.
- `CONFIG=Release … --alloc` → 0 (display-only, nothing on the render path).
- New pure tests (`RiffStackDotsTests`): onset→step→column, the fade curve, the state gates.
- iOS build. Device-owed (dot legibility, the corner placement, the fade feel) → one line in
  `Docs/euclideous-device-verification-debt.md`.

# RESETS V2 ferry — findings (mapping before the build)

Paul 2026-11-15, Draft 1 ratified. Display-only: no sound, storage, schedule or undo behaviour changes.
Mapped against source (the prior-ferry spec docs `claude/ferry-*.md` are not in this repo; code is the starting point).

## Gate — the prerequisites landed on `main`
- RESTART UNITS (slices A–D + review) incl. **FIX 1** `a3c578a`.
- RESTARTS EDITOR V2 `51d06a7..c5c5831`.
- RESETS tab `0219b52..48053f4` (the tiles moved onto the lane card, pop-up hidden).

## The tile as built on the RESETS tab (file:line)
- Mount: `resetsTabContent` `Fourfold/UI/EuclideousPage.swift:3456`; `restartTile:3525` → `restartTileLayer:3551` stacks `euclideousRestartTileLayerOrder` = base·sweep·track·text (`Derivations.swift:10136`).
- `.base` `:3554` — radius 8; fill `#22252C` (set) / `#2A2D34` (FREE); 1 pt lane100 border (set).
- `.sweep` `:3558` — **the outer fill**: `EuclideousRestartTileCanvas(.sweep)` → `RestartTilePainter.swift:38` `drawSweep` (lane100 @ 30 % + a 2 pt leading edge, width = tile × `state.progress`).
- `.track` `:3562` — **the inner strip**: `EuclideousRestartTileCanvas(.track)` → `RestartTilePainter.swift:49` `drawTrack` (x10..W−10, 12-tall box bottom at height−6, 6-tall cells).
- `.text` `:3566–3593` — name line `arrow.clockwise`(8 pt) + "RHYTHM"/"MELODY" (8 pt heavy, tracking 0.8, **ink `#8A909A`** `:3571`); value group HStack `:3576` = link glyph `link`(10, lane100) `:3578` · 7×7 source square (lane100 of source) `:3582` · value (13 heavy, **set `#F2F4F7` / FREE `#AAB0BA`**) `:3585` · unit (8, `#8A909A`) `:3587`; padding `.horizontal 10 .top 6` `:3592`.
- Pure fns behind sweep/track: `restartTileState` `Derivations.swift:10198`, state struct `EuclideousRestartTileState:10101`.
- Pure tile text layer: `euclideousRestartTileSpec` / `…Fit` / `…Label` `Fourfold/Engine/RestartEditorUI.swift:27/50/70`.
- **Tile frame:** `euclideousResetsCardLayout` **T = 44** (`RestartEditorUI.swift:206`), x 0 × TW × 44 in every layout case (cases a/b/c shrink only the gap/row2/link, not the tile). Inner-strip built bottom = **height − 6**. A 10-tall ruler ending there → top at y 28; top text row ≈ y 6–14 → ~14 pt clear; §1.2's "within 4 of the name" is not tripped at T = 44 (the exact name-glyph bottom is device-owed).

## Schedule readers (RESTART UNITS §5.1)
Exist: `passIndex`/`passStart` (`Derivations.swift:6365/6369`, `RestartSchedule.swift:247/254`); `rhythmOriginBeat`/`melodyOriginBeat` (`:6331/6339`); `nextRhythmRestart`/`nextMelodyRestart` (`:6335/6361`, `RestartSchedule.swift:239/245`); riff-cycle `riffCompletions(before:)` / `riffCompletionCount(atOrBefore:)` / `riffCompletionBeat(k)` (`RestartSchedule.swift:289/344/358`); current unit **count** `euclideousRestartCurrentUnit` (`RestartEditorUI.swift:407`).
**Missing (to add in step 2):**
1. A **per-window block enumerator** — pass blocks (RHYTHM) and riff-cycle blocks (MELODY) overlapping a span, each (start,end,cut). Only by-index readers exist.
2. A **standalone running-link-index** reader (§3.6) — today derived only inside `euclideousRestartTimeline:380`.
3. A **riff-cycle natural-length-in-steps** reader (§2.1) — `euclideousRiffCyclePrediction:3090` returns a per-hit RANK LIST (count = hits/cycle), not a length in steps.

## `euclideousRiffCyclePrediction`
`Derivations.swift:3090` — returns `[Int]`: the 1-based rank (`column + 1`) each hit of ONE cycle reads, in time order (from `euclideousRiffCycleOrdinals`). It does **not** give the cycle's natural length in steps.

## Step length / barBeats as the tiles read them
The tile does **not** read them today (it shows unit/links). Available: lane step `sub` via the schedule lane `…data.sub` (`RestartEditorUI.swift:416`) or the walk `cfg`; `barBeats` via `clock.beatsPerBar` threaded as `EuclideousRestartEditorInput(barBeats:)` (`EuclideousPage.swift:3463/3601`).

## FREE dim / unit chips / source squares / count chips / link glyph
- **FREE dim:** `dim = active ? 1 : EuclideousLaneDimStyle.opacity` `RestartEditorViews.swift:239` — reuses the **global 42 % lane-dim** (shared with muted/solo lanes), NOT a RESETS-local literal. §3.3's 60 % is added as a NEW RESETS-local constant so it can't bleed into the shared lane dim.
- **Unit chips** `chip(_:)` `RestartEditorViews.swift:280–292`: `names = rhythm ? ["PASS","BAR","RIFF"] : ["HIT","PASS","BAR"]` `:281`; x anchors `[48,92,136]` (`RestartEditorUI.swift:224`, both halves) — already the spec's x, so §3.1 is reorder-only; the `unitIndex` map `[.hit,.pass,.bar]` `:233` and AX words `:430` change in lockstep.
- **Source square** `sourceSquare(_:)` `:294–317`: colour-only (no number); selected = fill, unselected = 1.5 pt stroke @ 55 %; the own-lane/unavailable square **is drawn** (dashed `#3A3E47`) + `.disabled`. §3.5 wants a centred lane number and the own-lane slot NOT drawn.
- **Count chip** `EuclideousCountChipView:73–124`: no progress bar today.
- **Link button** `EuclideousRestartLinkRow:40–70`: `Image(systemName: "link")` only `:56` (the hidden pop-up `:205` too) — §3.7 restores `arrow.down`.

## Contradictions / source-wins
- §3.3 "60 % (was 42 %)": the 42 % is the shared `EuclideousLaneDimStyle.opacity`, not a local constant → implement 60 % as a RESETS-local constant (do not edit the shared one).
- §1.9 name ink → `#C4C9D1` (source is `#8A909A`): an explicit change, not covered by "looks unchanged".
- `RestartEditorUI.swift` is under `Fourfold/Engine/` (CLAUDE.md said `UI/`); the `claude/ferry-*.md` spec docs are not checked in.
- §3.1 x anchors (48/92/136) already match; only order/labels/`unitIndex`/AX change.

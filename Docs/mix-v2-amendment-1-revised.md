# MIX v2 — AMENDMENT 1 (REVISED) — ratified spec

**Status: NOT YET BUILT. Owned by the MIX v2 ferry (in progress on `feature/mix-v2`, worktree B).**
Ratified by Paul, 2026-11-05, from the updated "MIX v2 · stacks" mockup in chat. This is the
authoritative text and **replaces any earlier "MIX v2 amendment 1"** — if an earlier amendment-1
was received, discard it and use this. It amends the MIX v2 ferry (2026-11-05): fold it into the
MIX v2 plan before building the band layout; where they disagree, **this text wins**, and every
section it doesn't name stands. Sizes are in pt at MIX v2's references; where source disagrees
about an existing value, source wins — report each difference.

Recorded here (2026-11-05, from worktree A, by the instance that had just landed RATCH EXPAND)
so the ratified text is durable in the repo and can't be lost; the amendment itself was NOT built
here — Paul's call was "goes with B / wait for MIX v2 to land." See the end for the state at the
time of recording.

> Paul's aims, from chat: the band's top line must align like the MIX rows build does today, where
> play sits over the pool column and SOLO over the A–D column. In v2: play is in the pool's column,
> HITS and STEPS are in the A–D toggles' column, and the framed rhythm strip runs between them; all
> three share the same top and height. The band reads as clean columns from top to bottom. No
> explanatory text anywhere in the interface: labels and values only.

## §B1 THE TOP LINE (amends MIX v2 §1.3, §2.2 and §2.4)
- **B1.1** One line, y 0–30 in the band's inner coordinates, holding three things with the same top
  and the same height (30):
  - Play: the left column, x 0–56, exactly the pool's x range.
  - The strip frame: the right block's x 0 to blockW − 113 (482.33 at the landscape reference, 511
    portrait), so its left edge is the plates' left edge and its right edge is the OCT control's
    right edge in the rows below.
  - HITS and STEPS: the right block's x blockW − 107 to blockW − 3 (488.33–592.33 landscape,
    517–621 portrait), exactly the A–D toggles' x range in the rows below.
- **B1.2** Play: the lane card's play tile view at 56 × 30: #26272C, radius 8, the triangle in
  lane100, centred, about 12 × 13. Same tap and undo. Target 56 × 36 from its top. It doesn't dim.
- **B1.3** The strip frame: MIX v2 2.2's fill, border and radius, with a 2.5 pt inset all round;
  inside, only the steps, filling it (MIX v2 2.3's cells and fills). Play and HITS/STEPS are no
  longer inside it.
- **B1.4** HITS and STEPS: two boxes, each 50 × 30, 4 apart, #1F2127, radius 7, outside the frame.
  Each: its number (the lane's hit count; its step count), 12 pt heavy, #F2F4F7, centred; under it,
  3 pt apart, "HITS" or "STEPS", 6 pt heavy, 0.15 em, #8A909A. They take no touches and don't dim.
- **B1.5** A locked lane's badge (tab strip 6.2): 25 × 25 inside the strip frame at its right end,
  2.5 pt in, and the steps end sp4 before it.

## §B2 THE POOL AND THE FORK (amends MIX v2 §3.1 and §3.3)
- **B2.1** The pool: x 0–56, y 36 to innerH. Eight chips, 2 apart: chipH = (innerH − 50) ÷ 8 (10.75
  at the landscape reference, 10.79 portrait). Text as MIX v2 3.1 (the name 8 pt, the rank 5.5 pt
  raised 2 pt); truncate, never shrink. If a name doesn't fit, report it rather than shrinking.
- **B2.2** The fork: from (56, (36 + innerH) ÷ 2), so 86 at the landscape reference, to each row's
  centre, with the same control points' x (63.8 and 62.2).

## §B3 TESTS (add to MIX v2 §11, test 1)
- In every layout from layout 5.3: play's x range equals the pool's; HITS and STEPS' x range equals
  the A–D toggles'; the strip frame's left edge equals the plates' left edge and its right edge
  equals the OCT control's right edge; play, the strip frame and HITS/STEPS share the same top and
  height.

## §B4 VOICEOVER
- **B4.1** Order in each lane, unchanged from MIX v2 10.1: play, the strip (its label now also reads
  the hits and steps: "Rhythm, 4 hits in 8 steps"), the pool, then the rows. HITS and STEPS have no
  element of their own.

## §B5 ACCEPTANCE (add to MIX v2 §12)
- In each band, play sits directly above the pool, the same width; HITS and STEPS sit directly above
  A–D, the same width; the strip frame runs between them, starting at the plates' left edge and
  ending above the OCT control's right edge; all three share one top and one height.

## §B6 DEVICE-OWED (add to MIX v2 §13)
- The band's columns (pool, row controls, A–D) read cleanly from the top line down.
- Pool names read on 10.75 pt chips.

## §B7 REPORT BACK
1. Whether MIX v2 had landed when you read this, and how you folded this in.
2. The play, strip frame, HITS/STEPS and pool frames in every layout from layout 5.3.
3. Anything here that contradicted the code.

Out of scope: anything not named here. When done, update the status log and pending tasks and ship
as usual.

---

## State at the time of recording (2026-11-05, worktree A)
- **MIX v2 had NOT landed.** `feature/mix-v2` (worktree B, `/Users/paulbarrett/src/midi_spark-b`)
  was 2 commits ahead of main: step 1 = findings (a one-line status-log note), step 2 = per-part
  solo (engine — Router/Models/Snapshot/Kernel + `PartSoloTests`). The MIX v2 **band layout** this
  amendment re-columns (pool column, A–D toggles column, framed strip, the fork, §1.3/§2.2/§3.1,
  "layout 5.3") was **not yet built** on that branch, and there is no MIX v2 spec doc in `Docs/`.
- Therefore §B7 could not be answered beyond #1 (no landed/written MIX v2 layout to amend) and #3
  (the whole amendment presupposes the MIX v2 band structure, which the landed **MIX ROWS** panel —
  769.33 × 610, bands + part rows + an A–D *emitters* column 76 wide — does not have; so every
  section contradicts current `MixPanel.swift` / `MixPanelViews.swift`, as expected for an amendment
  to an unlanded ferry).
- Build path: the MIX v2 instance (B) folds this into the MIX v2 band-layout step; or it is built on
  top once MIX v2 lands on main. It must NOT be built in a second worktree against a stub — that
  would collide with B on the MIX panel files.

# SPEC → Code — THE DICE: authoring randomization, instrument-wide
# (2026-08-05, Paul's direction: random cells · partial locks ·
# randomization authors MACROS · what else)

## THE PRINCIPLES (all rolls obey)
- **House-trained bounds**: rolls draw from CURATED musical
  distributions (rates from real divisions · gates 30–95 · chains
  1–3 slots weighted, 4+ rare · density-capped · dests only among
  enabled emitters). Never uniform-over-everything.
- **Seeded + visible**: every roll shows its seed; re-roll = new
  seed; a seed can be typed (shareable — "try 0x5A3F" is forum
  culture waiting to happen). Derive-law native.
- **One undoable step per roll**; roll-again REPLACES, never stacks.
- **LOCKS = pins**: any group (INPUT · each slot · OUTPUT · TRIGGERS)
  can be PINNED (a small pin toggle beside the group's 🎲); RANDOMIZE
  fills only the unpinned. Paul's core flow: set input/output + one
  processor by hand, dice the rest.
- **MUTATE vs ROLL**: every 🎲 long-presses to MUTATE (a bounded
  nudge of current values, ~±15%) — the evolutionary loop: roll,
  keep, nudge. Tap = fresh roll.

## THE SURFACES
- **The cell dice**: a 🎲 on the edit page (per-group dice + pins as
  above; the whole-cell 🎲 respects all pins). The brush gains a
  RANDOM variant: PLACE drops house-trained strangers.
- **★ THE DICE AUTHOR MACROS** (Paul's principle, promoted): a rolled
  machine also composes 1–2 bounded A/B deltas and BINDS them to
  free macro slots (named "ROLL-A"/"ROLL-B" until renamed) — random
  results arrive PLAYABLE, and the unset-panel problem shrinks
  further. Pinned macros are never touched.
- **★ THE LADDER GENERATOR**: roll 8 machines → SORT BY DENSITY →
  stamp a column (or 8 rows) — an instant intensity ladder from one
  die. Lives beside LADDER's controls + as a library action.
- **Scene MUTATE**: "mutate a COPY of this scene" (amounts · lane
  values · seeds nudged within bounds) — exploration under the
  scenes-are-precious law (always copy, never in place).
- **Pattern dice**: CHOP/GROOVE masks + lane RND fills roll with
  density bounds (the rhythm dice).
- **Library SURPRISE ME**: stamp a random factory chain.

## Sequencing honestly
The distributions are the design work (each param's musical range,
authored once, in one table the manual can print). Mechanism is
small; taste is the build. — design-side Claude

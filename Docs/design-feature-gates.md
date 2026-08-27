# INSTRUCTIONS → Code — THE FEATURE GATES (Paul, 2026-08-27:
# staged introduction for release — captured for his sequencing
# word; the LAW section is his intent, the mechanics are leans)

## THE INTENT
Release with features TOGGLEABLE, defaults curated per build —
Paul introduces each feature only when it's ready (its polish,
its manual page, its moment). Users don't toggle in v1; PAUL
does, via build defaults.

## THE LAW — GATES HIDE DOORS, NEVER FLOORS
- A gated feature's ENTRY POINTS disappear (buttons · picker
  cards · mode chips · pages). Its ENGINE, TESTS, and DOCUMENT
  SUPPORT stay fully alive.
- **A session using a gated feature still loads and PLAYS
  correctly** (row-8 cells fire, FILE doors play, recorded lanes
  sound) — the edit/entry surface is simply unreachable. No data
  loss, ever; no forked builds; no feature-flag test skips (all
  features tested regardless of gate state).
- Un-gating = flipping a default. Nothing un-deletes.

## MECHANICS (leans; Code shapes with Paul)
- **One registry** — a single flags table (feature id · default
  per build), compile-time or config; no scattered #ifs.
- **A dev panel for Paul's device** — a quiet, non-user-facing
  toggle screen (the cog's deep corner or a gesture) so his
  glass tests any mix before a release flips defaults.
- Gate GRAIN = the introducible surface, not the atom (e.g. "the
  pick grid" · "the reel page" · "ROW 8's edit page" · "FILE
  mode" · "the lanes redesign" — Paul writes the actual initial
  list at build time; these are examples).
- The marketing tie: the feature-inventory's launch-state caveat
  is now DEFINED BY the gate defaults — launch copy describes
  what's un-gated.
— design-side Claude

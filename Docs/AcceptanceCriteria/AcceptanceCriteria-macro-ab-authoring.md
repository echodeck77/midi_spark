# DESIGN REVISION → Code — MACRO AUTHORING BY A/B (supersedes the
# long-press assign flow) + THE THREE-BANK PANEL — 2026-08-03
_The user's ruling: long-press fails on sliders. The replacement:
sections carry A→B states; macros bind them. Authoring by
demonstration — the B state IS the depths._

## 1. THE [AB] BUTTON (per group on the Edit page)
- INPUT · each CHAIN SLOT (or the chain as one group — Code's call
  with the user on granularity) · OUTPUT each gain a small **[AB]**
  button in their divider row.
- Tap → **THE A/B POPUP**: the section's automatable controls
  re-rendered LIVE, with an **A—B slider at the top, auto-set to B**
  — so every tweak defines the B state while HEARING it at full.
  Dragging the slider auditions the morph A↔B before committing.
- The delta (B − A, per touched param) is what gets bound. Untouched
  params carry no delta (the macro leaves them alone).

## 2. THE BINDING LIST (below, in the same popup)
- **24 macro rows in three banks: 8 BUTTONS · 8 SLIDERS · 8
  TIMELINES** (timelines = the laned macros, promoted to their own
  bank). Each row shows its EXISTING assignments as chips
  ("R1·in" · "GOLD·slot2" · "OUT·B"); tap a row = ADD this section's
  A→B to it; tap an existing chip = remove that binding.
- Deltas are stored ON THE BINDING (macro × section), so two macros
  may hold DIFFERENT B states of the same section; overlaps sum and
  clamp per the offset law (the math is unchanged — B−A per param IS
  the depth vector; authoring changed, architecture didn't).
- Targets resolve to the selected cell(s)/twins per the edit page's
  standing write law.

## 3. THE THREE KINDS, unified
One binding model, three movers:
- **BUTTON** = snap A|B (discrete — and B may include enum/boolean
  flips: the staged rig-switch generalized; spring = momentary-B,
  padlock = latched-B).
- **SLIDER** = continuous morph A→B (spring/fixed as designed).
- **TIMELINE** = the 8-step lane drives the morph value per column
  (SMOOTH|STEP as designed; per-scene capture unchanged).

## 4. THE PANEL RESTRUCTURE (surface vs depth, per the overlay rule)
- The perform-surface panel shows **one bank at a time** (a small
  BTN | SLD | TML selector; sliders default) in the FLOW-succession
  slot — eight controls visible, the house density.
- The panel's **advanced view** (grid overlay, per the overlay rule)
  = all 24 with names, assignments, padlocks, lane editors — the
  management surface. Tap a macro's name there for rename/detail.

## 5. What dies / survives
- DIES: long-press assign · per-target numeric depth/invert UI (the
  B state encodes both — invert = a B below A).
- SURVIVES unchanged: the offset math · spring/padlock · AU-param
  exposure (sliders bank first) · announce/ghost-thumb tells ·
  chrome-quiet · lane mechanics.
— design-side Claude

## §6 — GRANULARITY RULED (user, 2026-08-03): PER GROUP
Three [AB] groups: **INPUT · CHAIN (one popup, ALL slots' params
together) · OUTPUT**. Rationale: authoring-by-demonstration only
works if the COMPOSITE auditions — gate-with-rate is heard, not
computed. A B state may span multiple slots' params; it is defined
and previewed as one destination. (My per-slot lean withdrawn.)

## §7 — THE MOVER ELIGIBILITY RULE (the boolean answer)
The click danger was never discreteness — it was the SPRING-RELEASE
(a fader re-crossing a threshold). Two movers snap safely:
- **Continuous-only B → any mover** (button · fader · timeline).
- **B containing ANY switch (bypass, enum flip) → BUTTONS and
  STEP-TIMELINES only** (tap-snapped or column-boundary-snapped —
  both click-safe; the column-switched rig change survives).
- **FADERS and SMOOTH timelines never carry discretes.**
- **The popup teaches it live** (tweak-first flow preserved): the
  moment a switch is touched while defining B, the fader and
  smooth-lane assignment rows DIM — "this B contains switches,"
  said without words. Un-touch (revert the switch) and they relight.

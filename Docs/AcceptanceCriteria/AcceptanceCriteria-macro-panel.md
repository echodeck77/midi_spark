# AcceptanceCriteria — THE MACRO PANEL (captured 2026-08-05)

**STATUS: CAPTURED, NOT BUILT.** Spec of record for the future macro panel. User-confirmed capture-only on the
`feat/multiple_features` branch — it wants its OWN branch (it adds an offset term to the effective-param resolution
stack + a perform-surface panel + a long-press assign flow + AU M1–M8 parameter registration + the CC rail). The
verbatim design ferry follows.

---

# DESIGN → Code — THE MACRO PANEL: perform-surface reach into the
# cells, as MODULATION (2026-08-02)
_The user's ask: processor settings retreated into cells; restore
perform-surface control via macros. The model that makes it clean:
**macros MODULATE, never rewrite** — an offset bus over the param
space, riding the interpolation stack._

## 1. THE MODEL
- Each macro m ∈ M1…M8 holds a value 0…1. A TARGET = (cell, slot,
  param) with DEPTH (±) and optional INVERT.
- **effective = base ⊕ (value × depth)**, applied at derivation via
  the effective-params/interpolation stack. Bases are NEVER written.
- Consequences by construction: twins stay twins (bases equal → seals
  stable; the macro layer is performance, not identity) · macro→0 =
  home (nothing to revert) · scenes store BASES (macros ride on top;
  macro values GLOBAL v1, per-scene later if wanted) · no undo spam
  (macro motion is performance-class, not edits).

## 2. THE PANEL
- EIGHT nameable macro faders (default M1…M8), living in the retired
  colour desk's region on the perform view. Tap a name → the macro's
  DETAIL popover: target list (cell·slot·param), per-target depth /
  invert / remove; RENAME.
- House look: slim vertical faders + name chips; values visible;
  chrome-quiet at zero (unridden macros recede).

## 3. ASSIGNMENT (where the params live)
- On the Edit page: LONG-PRESS any continuous control → ASSIGN TO
  MACRO ▸ M1–M8. The param row gains a small macro tag (Mn).
- One macro, MANY targets — across cells, slots, and the emitter role
  amounts (DUCK amount · LEAK % · ALT count excluded v1 if enum-ish).
- V1 scope: CONTINUOUS params only (gate · spread · tilt · depth ·
  time · chance % · role amounts). Enums/stepped later.
- **Twin semantics = the edit-page law**: a write-time target resolves
  to the cell's current twin-set… but under the offset model this is
  moot for identity (bases untouched); the offset applies to the
  TARGET CELL's derivation; assigning while a twin-set is selected
  targets the SET (one tag each).

## 4. THE ANNOUNCE LAW
- A ridden param shows a TELL on the Edit page: the base thumb + a
  ghost at the effective value (and the Mn tag lit while the macro is
  non-zero). Nothing moves mysteriously — the deviation law's
  modulation clause.

## 5. THE TWO CONVERGENCES
- **AU PARAMETERS**: expose M1…M8 as the plugin's automatable params.
  The automation story (orphaned since morph retired) is reborn: AUM
  lanes, host MIDI-learn, hardware — all ride the macros, zero
  MIDI-learn code of ours.
- **THE CC RAIL lands here**: future CC-in mapping = external control
  of the macro panel (CC# → macro). One modulation architecture,
  three doors: fingers · host · wire. The rail's consume/announce
  pins apply unchanged.

## 6. Sequencing honesty
Needs: the offset layer in effective-param resolution (the stack
exists; this is one more term) · the panel UI · the long-press assign
flow · AU param registration. No engine derivation changes beyond the
term; replay-safe (macro values are inputs like any control).
— design-side Claude

## §7 — PANEL DESIGN RULINGS (the user's four questions, 2026-08-02)
- **FADERS: confirmed.** Vertical, slim, ×8 — the house grammar (strip
  touch model, marks language, HOLD capture inherited). Unipolar 0…1,
  zero at the foot = visible home (the offset model's soul). XY pads
  parked as a someday alternate view.
- **SPRING | FIXED, per-macro, SPRING default.** A tiny PADLOCK at
  each fader's foot toggles (the LATCH iconography, already taught).
  Spring composes with the global HOLD latch (lean in, HOLD through
  the drop, release). PIN: spring is a TOUCH behaviour — host-
  automation/CC writes set values absolutely, no spring fight,
  last-writer.
- **THE ASSIGN FLOW**: long-press any continuous Edit-page control →
  compact popover: "ASSIGN TO MACRO" + the 8-chip row (names shown,
  occupied = dot) → tap = assigned (toast "GATE → M3"); the param row
  wears an **Mn tag** (tap tag → depth ± · invert · remove). Panel
  side: tap a macro's NAME → detail sheet (targets · rename ·
  spring/fixed). One flow; no roaming assign mode.
- **REAL ESTATE**: ≈ the MIDI INPUT box footprint — 8 × ~48pt faders
  + gaps (~440–480pt wide), ~150–170pt tall for honest travel. Lives
  in the retired colour-desk band; landscape beside MIDI OUTPUT,
  portrait its own row. Chrome-quiet: zeroed macros recede, ridden
  glow. Name chips at the head (4–6 chars, tap = detail).

## §8 — MACRO SHAPES: FADER | BUTTON (the boolean answer, 2026-08-02)
The user asked whether faders should drive on/off targets. NO —
booleans get their own shape; thresholds-on-springs would click on
release, and triggers can't reach multi-cell from the panel.
- **Slot type chosen at creation: FADER (continuous targets only) |
  BUTTON (boolean targets: slot bypass · chop-flip · redirect · role
  toggles).** Buttons take multiple targets with per-target INVERT
  (the switch see-saw: un-bypass here, bypass there).
- **THE PADLOCK UNIFIES**: FADER+spring = lean/release · FADER+fixed
  = park · **BUTTON+spring = MOMENTARY** (panel-level PUNCH-IN across
  cells) · **BUTTON+fixed = TOGGLE** (latched rig-switch). One glyph,
  four behaviours.
- Division of labour, on record: TRIGGERS = cell-local touch ·
  BUTTON MACROS = composed multi-cell switching from the panel ·
  FADERS = continuous only.
- **V2 spice, recorded not built**: boolean targets with a per-target
  THRESHOLD % on **FIXED faders only** — the staged BUILD fader (the
  rig assembles as you push). Spring+threshold stays refused (the
  release-click).
- Assignment: long-pressing a BOOLEAN control on the Edit page offers
  only BUTTON macros in the chip row (shape-matching enforced at
  assign; no mis-wires possible).

## §9 — THE UNSET STATE (Paul's question, 2026-08-04: blank projects)
Three layers, two already law:
- **Factory + DEFAULT ship bound**: every factory preset's macros are
  pre-composed and NAMED (standing rule), and THE DEFAULT first-run
  doc ships with working macros — first contact never meets a dead
  panel.
- **Unset slots are INVITATIONS, not blanks** (the sparse grammar:
  capacity is invitation, not furniture): an unassigned slot renders
  dim/dashed with a small +, and TAPPING IT opens the assignment
  flow (the A/B path / the MACROS tab pointed at that slot). On a
  blank project the panel reads as sixteen doors, not sixteen dead
  controls.
- **Chrome-quiet on the bank**: unassigned recede (dim, unnamed);
  bound slots sit lit with names — the panel's visual weight always
  equals its real power.

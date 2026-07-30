# AcceptanceCriteria — cells-and-colour-desk.md (the visual overhaul)
_Given/When/Then, plain language, per the verbs-behaviour.md convention.
Scope: the LOOK of cells, the colour palette, and the colour/processor
desk. Design details for Code at the foot. Parts A–B are ratified
design; Parts C–D are the user's direction from 2026-07-29 — build in
order, confirm sequencing with the user at the C/D boundary._

## PART A — THE CELL FACE
**A1. The resting occupied cell**
- Given a cell wearing a Colour, when the grid is at rest, then the
  cell shows: its Colour as the block · the Colour's EMBLEM (the type
  glyph) leading · the params digest small and dim (the v59 grammar:
  rate · oct · ∞ · transpose, deviations only) · up to four small BUS
  DOTS at the foot (lit = that emitter enabled).
**A2. Input attribution (the compass tint)**
- Given a cell whose input is a ROW, then a slim tint in the PARENT's
  hue sits on the PARENT-FACING edge (parent above → top edge; below →
  bottom edge).
- Given a cell whose input is a receiver, then NO edge tint shows
  (default recedes).
**A3. The trigger glyph (deviation-shown)**
- Given a cell whose TAP action is the default, then NO trigger glyph
  shows.
- Given a non-default TAP action, then a small glyph sits in the
  bottom-right position (↻ replay · ⇄ flip · ↑/↓ octave · ❄ freeze —
  one mark per action in the shipped TRIGGERS roster).
- Given a non-default HOLD action, then the same glyph position wears a
  RING modifier. Never more than two marks.
**A4. States**
- Given an empty cell, then it shows only its watermark row number.
- Given a cell selected or placed-this-hold, then its outline is WHITE
  (the canon; no amber anywhere).
- Given a hidden-pending-clear cell, the existing ring behaviour stands.

## PART B — THE DESK (colour/processor panel)
**B1. The title-as-picker**
- Given the desk pointing at a Colour, then each processor panel's
  title row reads: [EMBLEM] TYPE ▾ · COPY · PASTE — the current type
  always visible, its emblem beside it, tinted in the Colour's hue.
- When the user taps the type name, then a PICKER POPOVER opens: one
  row per type — emblem · NAME · a one-line description. Selecting
  retypes the panel (params reset per the standing retype rules).
- Given panel B, its picker leads with OFF ("no B-side"); panel A's has
  no OFF.
- Then the old segment rows no longer exist anywhere.
**B2. Emblems**
- Given the six types, each has ONE emblem (ARP = the climb · RTC = the
  burst · PASS = the gate · STRM = the fan · CHNC = the die · HARM =
  the bloom). Cells and titles draw them STATIC. (The animated "living
  emblem" pass is a later, separate wave — the picker zoo may animate
  then; nothing animates in this wave.)

## PART C — NAMES (ownership, optional)
**C1.**
- Given a Colour, it has an optional NAME (text), defaulting to its
  type name.
- When the user edits the name (via the desk title area), then the
  palette chip, the desk title, and INSPECT cards show it.
- Given no custom name, everything shows the type name — zero-effort
  users see today's labels. Names never replace the emblem (the glyph
  stays the mechanism-truth; the name is the user's word).

## PART D — THE SPARSE PALETTE (the user's ownership direction)
**D1. Slots**
- Given a document, the palette shows its DEFINED Colours as chips
  (hue + name) plus "+" slots for the undefined remainder (16 max).
- Given the DEFAULT preset, it ships with only the arc's Colours
  defined (3–4); the rest are + slots.
**D2. Creation**
- When the user taps a + slot, then the TYPE PICKER opens (the B1
  popover, reused) — choosing a type BIRTHS the Colour (hue = the
  slot's default from the standard wheel; name = the type).
- Given a PLACE hold, when the user taps +, the same picker opens and
  the new Colour becomes the brush — creation never exits the hold.
**D3. Protection (scenes-are-precious sibling)**
- Given a Colour with any cells painted (census > 0), it cannot be
  deleted; the desk shows its census.
- Given census = 0, the desk offers a small delete control; deletion is
  undoable.

## EXPLICIT EXCLUSIONS (do not build in this wave)
- TRIGGERS remain Colour-side (the per-cell split is a separate,
  unratified restructure).
- Per-cell parameter OVERRIDES: separate future.
- Animated emblems: later pass.
- The emblem + glyph ARTWORK is an asset task — placeholder-quality
  glyphs are acceptable for this wave's acceptance; the drawing job
  follows.

## DESIGN DETAILS for Code
Budget: cells draw static only (no timers; the invisible=frozen law
applies to any future animation). Deviation law governs every mark
(defaults invisible; divergence announces). The digest grammar is the
shipped v59 field set — no new fields. White selection per the
verbs-behaviour canon; check emblem/white contrast on pale hues. The
compass tint = the input-attribution resolution (slim, whisper-weight,
never competes with the block). Bus dots replace any chip-row treatment
on the face. Hue defaults = the current sixteen-wheel, per-slot.
Names are the app's second text input (preset names were the first) —
reuse that keyboard handling. Palette census = a cheap derived count.
— design-side Claude, 2026-07-29

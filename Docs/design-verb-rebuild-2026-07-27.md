# Design ferry — the AUTHORING REBUILD (items 8–12, 2026-07-27)
_Ferried + preserved 2026-07-27 from PENDING-FERRY.md. Items 1–7b were already preserved (design-ferry-modeless
+ design-epoch-arrangement-presets-cog) and are largely BUILT. THIS file holds the NEW authoring epoch: the cell
face, chain geometry, spatial routing, the five round HELD verbs, and THE DEMOLITION. Status: **DIRECTIVE** = build._

## 8. THE CELL FACE rev — NAMES · EMBLEMS · WHISPERED WIRING (PROPOSAL; awaiting user's trio)
- **NAME THE COLOUR, NOT THE CELL**: the Colour's name field becomes USER-EDITABLE, defaulting to the processor
  type; cells + palette chips show the Colour's name. Per-Colour (16, edit-once), not per-cell. Zero-effort users
  see today's face (default IS the type).
- **THE EMBLEM disambiguates the custom name** ("[climb] BASS" = role + mechanism). Renaming + emblems require
  each other — sequence together (P2).
- **WIRING WHISPERS**: A B C D chips shrink to FOUR TINY DOTS at the foot (lit = enabled); row-feed = a subtle
  top-edge tint in the parent's hue.
- Digest (rate·oct·∞) stays small+dim, below the name. ANATOMY: Colour block · [emblem] NAME · digest · four
  dots · edge tint when row-fed. AWAITING the user's word on: ① per-Colour naming ② dots-not-chips ③ edge tint.

## 9. CHAIN-GEOMETRY TENSION — downward-only constraint REJECTED
Spatial order ≠ signal order (references may climb). Resolution: **① COMPASS TINT** — the row-feed edge tint sits
on the PARENT-FACING edge (parent above → top edge; below → bottom); climbs announce themselves. **② REFRAME**:
the grid is PLACEMENT, INSPECT is ORDER — the route panel draws every chain L→R in true signal order regardless
of geometry. **③ DOWNHILL NUDGE**: placing a child, the cell directly BELOW the parent pulses first among
candidates (a default, no law). **④ TIDY** (awaiting user): a per-column, user-invoked, undoable sort to read
top-down — trade: can break cross-column row identity. Never automatic.

## 10. SPATIAL ROUTING — "the layout becomes the patch bay" (PROPOSAL, pinned)
During PLACE/AUDITION, wiring happens by POINTING AT THE WORLD:
- Place a cell → candidate SOURCES light as **ROUTE IN** where they sit: the four RECEIVERS (large) + OCCUPIED
  cells in rows ABOVE (empties don't light). **Single-select radio** (one input; new tap releases old).
- Candidate DESTINATIONS light as **ROUTE OUT**: the EMITTERS (multi, made large/geographic) + OCCUPIED cells
  BELOW — tapping a below-cell RE-POINTS THAT CELL'S INPUT to this row (fan-outs by tapping several; undo per tap).
  [v2, not built: tap an EMPTY below = place-and-wire a child in one gesture.]
- The one-home law bends: the session is home; the bands/rows wear a SESSION FACE (large labeled in-hue targets)
  for the duration; revert on DONE; **the engine never pauses**. v1 scope: PLACE/AUDITION only; EDIT keeps the panel.

## 10b. CHAIN SURGERY under spatial routing (two laws)
- **① TREATMENT SWAP = no re-wire**: recolour/edit the link in place; wiring persists (the LIVE LAW).
- **② SPLICE-IN**: place NEW between A,B → ROUTE IN tap A → ROUTE OUT tap B (re-points B). Three touches when a row
  gap exists; squeezes use the escape hatch (edit the child, re-point at the panel head) or MOVE first. CRAFT NOTE:
  factory content models row gaps so every splice is three touches.
- **③ INHERIT-ON-DELETE LAW**: deleting a cell, its CHILDREN INHERIT ITS INPUT (chain-fed → re-point to grandparent;
  receiver-fed → hear the receiver). One undoable step, no confirm. Orphan-silence never happens by accident.
- **④ LINK REORDERING**: panel territory v1; a gesture waits until missed.

## 10c. MULTI-INPUT CELLS — YES; staged
The engine's laws already pay for it (pools union, per-source refcount; each parent resolves under would-be-output;
cycle-safe). PAYOFF: **MERGE CELLS** (harmonize/gate/dice the union of two chains). **RECOMMENDATION: schema becomes
a SET NOW** (single-source docs encode unchanged — migration no-op) · **UI single-select v1** (radio holds) ·
**multi = a UI flip later** (toggles, one release note, zero migration). THE CALL IS THE USER'S.

## 11. ROW BUTTONS + FIVE ROUND VERBS — PLACE · REMOVE · SELECT · MOVE · COPY (PRIORITY; supersedes INSPECT/COPY/EDIT/AUDITION)
- **ROW SELECT BUTTONS** (slim, left of each row): tap = the row becomes the selected noun (cells flash); every verb
  acts at row scope; re-tap deselects.
- **THE MERGERS**: INSPECT + EDIT dissolve into **SELECT** — selection SHOWS (route panel + processors), looking is
  free, touching edits (live, undo-covered); scope chips (+n TWINS · ALL <COLOUR>) live in the panel header. MOVE +
  REMOVE promote to first-class verbs.
- **PLACE** = the audition flow (stamp-seeded pending cell · spatial ROUTE IN/OUT · pulsing empties · live preview ·
  repeat-place). **REMOVE** = tap cells/rows, gone in one undoable step, children inherit the input (10b). **MOVE** =
  lift-tap, land-tap (empty=move, occupied=overwrite-with-undo). **COPY** = source-ring → stamp → paste.
- Buttons ROUND AND INVITING (a warmth cue, on record). Coverage: all prior flows map; nothing orphaned.

## 11b. CORRECTION — THE VERBS ARE HELD, NOT ARMED (the two-finger quasimode; supersedes 11's activation)
**Hold a verb; the grid invites; taps do the verb; release = done.** The armed-state apparatus dissolves (no radio,
no lit management, no cancel — release IS the exit). The §5c spring class arrives at the verbs. PERFECT SEPARATION:
no verb held → taps are TRIGGERS; held → taps are the verb.
- **PLACE**: hold → empties pulse + ROUTE IN lights; tap source → wire; tap empties → wired placements (live
  preview); release = committed.
- **REMOVE**: hold → tap cells/rows → gone (heal law); release done.
- **SELECT** (result OUTLIVES the hold): hold → taps TOGGLE membership → release → selection persists, panels show
  it, both hands free → touching edits (live, scoped via chips) → DONE/tap-away deselects.
- **MOVE**: hold → lift-tap, land-tap (empty=move, occupied=overwrite-with-undo), repeat; release done.
- **COPY — the ceremony dies**: hold → first tap = source (stamp) → every subsequent tap PASTES DIRECTLY (the hold
  is the confirmation context; undo per paste); release done.
- Row buttons compose with every held verb. PINS: verbs **bottom-left** (thumb-anchor ergonomics — confirm on
  device) · **accessibility LATCH: long-press a verb = latches** (one-handed fallback; tap again releases) —
  spring|latch applied to the verbs themselves.

## 12. THE DEMOLITION — remove ALL existing editing before re-engineering. MAKE THIS BEAUTIFUL.
**REMOVE NOW** (clean slate, not phased — the phased-retirement pin is superseded):
- The EDIT/PERFORM toggle (the mode dies today).
- GRID CONTROLS as-built — the INSPECT/COPY/EDIT/AUDITION row + their flows (increments ①/②-core come OUT; **the
  DEVICE CHECKPOINT dissolves** — increments ②b–⑤ are cancelled, not paused).
- All EDIT-gated editing machinery: old cell-edit gestures, staging-mode remnants, any CELL-box vestiges. Perform
  gestures become TRIGGERS-only, everywhere, immediately.

**SURVIVES** (the perform instrument, whole): grid + TRIGGERS dispatch · the strips (single-face) · MASTER · FLOW +
thumbnail (and **the RouteRenderer** — it outlives the verb UI; SELECT needs it) · the scene strip · presets · the
cog page · all engine/document machinery (the schema keeps every field; demolition is UI-only).

**ACCEPTED WINDOW**: while demolished, the instrument cannot edit cells (presets/factory/T-loader still load
content) — dev-acceptable, user-owned.

**THE REBUILD BRIEF — beauty is the acceptance criterion**: the five ROUND held verbs (11/11b) + row buttons +
spatial routing (10/10b/10c staging per the user) + the arrangement bar (7/7b ✓) + the cog (6b ✓) + presets (3–3c ✓)
+ the cell face (8, pending the user's trio) — built under the polish laws (item 1: musical colour LOUD, chrome
QUIET, defaults RECEDE) from the first commit, not applied after.

## USER SPEC ADDITION (2026-07-27, in-chat): THE BUTTON LAYOUT
The round-verb cluster's layout, per the user:
- **Top row: PLACE · HOLD**
- **Second row: DELETE (=REMOVE) · SELECT**
- **The rest (Code decides): MOVE · COPY** — a 2×3 grid of six round buttons.
- HOLD = **CONFIRMED (user, 2026-07-27)** the §5c HOLD latch (the global gesture-sustain / "the drop"), given a
  first-class round button in the cluster beside PLACE.

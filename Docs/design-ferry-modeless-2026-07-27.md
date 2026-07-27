# Design ferry — the MODELESS instrument, FLOW cargo-colour law, TWO LATCH modes, TRIGGERS rename
_Ferried from the design-side Claude, consumed 2026-07-27. Preserves the rulings/directives that arrived
in `PENDING-FERRY.md`. Status tags: **DIRECTIVE** = build; **RATIFIED** = law; **PROPOSED** = awaiting the
user's ratification (design record only, do NOT build); **FUTURE** = roadmap, no build/sequencing._

## 1. FLOW hop-colour law — DIRECTIVE (bug fix, applies to FlowView + thumbnail + future spine)
Observed in scene 6: a row-1 → row-2 reference hop drew its line/comets in the CHILD's colour. **THE LAW:
A HOP WEARS THE COLOUR OF ITS CARGO (its source).**
- ENTRY hops (receiver → cell) = the RECEIVER's identity hue.
- REFERENCE hops (parent row → child) = the **PARENT's** colour (the parent's output is travelling; it is
  not the child's until transformed).
- EMISSION hops (cell → emitter) = the EMITTING cell's colour.
Chains then read as transformations (gold flows in, magenta flows out). Provenance: the as-built matched the
v62 mockup, which had it wrong — the bug is inherited from the drawing; the correction upgrades the law.
→ **Folds into FLOW slice 2** (the withheld comet-fizzle pass), since both are FlowView edits.

## 9. TWO LATCH MODES — DIRECTIVE (per-receiver: CHORD | ADD)
- **CHORD** (as built): detect-and-replace.
- **ADD** (new): note-toggle accumulation — while latched, each note-on TOGGLES membership in the frozen
  pool (play = joins; replay the same note = leaves). Makes the latch SCULPTABLE (build a cluster note by
  note, thin it, walk a drone through voicings). No chord detection.
- **Latch-off releases all — identical in both modes** (the one-release law survives).
- Mode is RIG CONFIG: a per-receiver CHORD|ADD segment on the strip's EDIT face (beside cable/channel,
  persisted structure). The PERFORM button wears a mode mark: **LATCH** vs **LATCH+**.
- ENGINE: the shipped frozen-NotePool chassis; modes differ ONLY in the update rule (replace-set vs
  toggle-membership), Kernel-side. Device exercise grows one line (ADD: join/leave/latch-off).

## 5. RENAME — the "ON" system → **TRIGGERS** — DIRECTIVE (prose only)
"ON" fails as a bare label. New name **TRIGGERS** (Elektron trig-condition recognition; precise scope
events→actions; row fit: "TRIGGERS: TAP — flip to B" parses itself). Mechanics: **section header + spec
prose rename only** — the five rows keep their names (TAP · HOLD · ARRIVE · LEAVE · SCENE), menus/axes/
greying untouched, **code identifiers STAY** (`OnConfig` etc. — the no-rename rule holds). The glossary's
"ON — the trigger system" entry promotes its definition to the name. (BEHAVIOUR = standing runner-up.)

## 10. PRINCIPLE — every panel shows its process (the 5th renderer family) — sequenced AFTER layout
State says what things ARE; process says what they're DOING. Per panel:
- MIDI INPUT: velocity marks + latch pips + entry pulses draining toward the grid.
- GRID: item 10's living layer (glyph derivation + live-column comets).
- MIDI OUTPUT: Colour-tinted marks + **hollow withheld tells** (← SHIPPED, strip slice) + **THE ALT BATON**
  (a dot on the current turn-holder's strip, passing as turns spend — hocket made visible) + FLATTEN's duck
  as a brief compression shimmer on scaled marks.
- MASTER: the confluence — strip pulses merging into the sum.
- PROCESSOR PANELS: the living emblems ARE the process view.
- PALETTE: chips glow faintly while their Colour sounds anywhere (dead chips = safe to repurpose, visibly).
- TRIGGERS: assigned rows flash as their events fire. SCENE strip: active slot breathes at each wrap.
ONE SYSTEM: the 5th renderer family on the shared derivation engine (theater · thumbnail · spine · route
panel · per-panel ambient); one intensity setting (OFF/SUBTLE/SHOWCASE); budget law (visible panels only,
derivation clock, no timers). SEQUENCING: after layout finalizes — panels must stop moving before they breathe.

---

## THE MODELESS INSTRUMENT — PROPOSED (complete design, awaiting user ratification; do NOT build yet)
Grammar change: mode-then-gesture → **VERB-THEN-NOUN**. Cell taps are ALWAYS the perform action; editing
ALWAYS begins with a labeled verb. **BASE LAW (ratified within the proposal): the grid's default IS the fun**
— press/hold are always the configured TRIGGERS actions; no mode gates performance.

**Four verbs** (GRID CONTROLS palette, in the space the colour selector vacates by moving beside PROCESSOR):
- **INSPECT** — momentary; replaces OUTPUT+MASTER with the ROUTE PANEL, dismiss restores.
- **COPY** — pick source (writes THE STAMP) → targets flash → press any flashing target = ALL commit (one
  undoable step); stays armed to re-stamp; re-tap COPY discards pending. Copies CELLS (panel COPY buttons
  copy PROCESSORS — two clipboards).
- **EDIT** — **SCOPE COMES AFTER TARGET**: tap EDIT → tap the exemplar cell (panel opens on THIS ONE with
  counted expansion chips: "+ n TWINS · ALL <COLOUR> (n)") → route panel WRITE-ARMED (banner states the
  truth: "EDITING 7 · ALL GOLD") → rewire on the map → recolour from palette → emblem tap focuses PROCESSOR
  panels → DONE. Two taps to editing, zero taps to save (LIVE LAW = the commit).
- **AUDITION NEW CELL** (= ADD) — the route panel opens WRITE-ARMED seeded from the stamp, a PENDING (dashed)
  cell card between head and tails; empty cells pulse; TAP-PLACE repeatedly; chip-drag survives as the
  quick accelerator.

**THE ROUTE PANEL (INSPECT read-only / EDIT write-armed — one panel, two doors).** Messiness dissolves by
model law: references resolve WITHIN-COLUMN, so a cell's complete lineage = its column's subgraph (one
upstream chain, a possible downstream fan, receivers at the head, emitters at the tails, ≤8 deep). Title:
"INSPECTING · COLUMN n". Layout left→right: receiver chip (identity hue) → ancestor cards → THE CELL
expanded → children cards → emitter chips. **Edges in CARGO colours** (item 1 law). ALIVE: comets run the
edges while playing (the flow engine's 4th renderer); the WITHHELD TELL renders here too (claim-killed
branches fizzle hollow — the PASS→ARP confusion class dies on this panel). Every node card shows THE EMBLEM
PAIR (A always, B beside when set, the ACTIVE face ringed live). Editing ON the map: head = input selector,
tails = bus toggles, emblem tap = PROCESSOR A/B focus (map edits WIRING, panels edit SOUND). Grid flashes
the true selected set; panel = workbench, grid = truth. MOVE = drag the exemplar; DELETE = CLEAR on the
panel (batch delete free via scopes: EDIT → ALL GOLD → CLEAR).

**THE INTAKE** — name for the input stage (source, transpose; future: key range/splits, velocity window,
scale-snap, pool-sampling). Home = the route map's HEAD, both doors. Tier 1 = the chip (digest + a DEVIATION
BADGE "⇐R2 · ▸2" = two non-default options; defaults invisible, deviations counted). Tier 2 = the INTAKE
CARD (source radio + FROM ROW + option rows in the ACCORDION discipline). GUARD: intake owns INPUT, panels
own TREATMENT, forever (the boundary that keeps "heavy" from becoming everywhere).

**Item 8 ruling (GRANTED, wording clarified 2026-07-27): the route panel owns all CELL WIRING (a cell's
input source + its bus MEMBERSHIP); the palette only ever chooses Colours.** The wiring toggles are DELETED
from the colour grid (not greyed — deleted). The CELL box dissolves into the route panel (INPUT→head,
OUTPUT→tails, TRIGGERS→the card, PREVIEW→the panel's button).
**Roles ruling (2026-07-27): EMITTER-LEVEL properties STAY ON THE STRIP** — CLAIM/FLATTEN/ALT/OCT, channels,
mutes, solos, faders. Two different nouns, no collision: the panel's emitter chips answer "which emitters
does THIS CELL feed" (membership); the strip's role buttons answer "how do the emitters treat EACH OTHER"
(output-shaping structure + performance surface). The mixer-as-instrument design survives modeless whole.

**Phased retirement:** EDIT mode survives as a shrinking legacy door until the strip SPANNERS
(receiver/emitter config doors) land; then the mode dies. **STATUS: the modeless design is COMPLETE, awaiting
the user's ratification to become the directive.** (Impact if ratified: supersedes the a5/a6 cell-editor
plan, the CELL box, and the receiver/emitter toggles at the palette.)

## FUTURE roadmap — logged, no build, no sequencing
- **6. Velocity-pad / Launchpad support ("the spatial twin"):** pad velocity restores TAP-REPLAY dynamics;
  poly-aftertouch = MORPH-SCRUB (address exists today); a Launchpad = an 8×8 RGB grid for 1:1 pad↔cell +
  LED mirror out one of the five cables (the input-cables architecture already accommodates a private cable).
  Needs a controller-mapping layer — standalone-era territory.
- **7. Finger drumming — two surfaces:** the 8×8 = drumming the ARRANGEMENT (TAP-REPLAY = the drum hit;
  REPLAY needs a CUT|LAYER axis, default CUT; CLAIM already IS choke groups; cheapest deliverable = THE KIT,
  a playable chord-drum-kit factory scene). The COLOUR GRID = drumming the ROSTER (palette tap = a one-shot
  STRIKE, the pool fired once through that Colour as a virtual cell).
- **7c. Palette-strike RESOLUTION (decided): (c) HARDWARE-ONLY, parked past v1.** Glass palette selects,
  period; strikes ship with the Launchpad layer. The tap-to-edit-sound vs strike collision (7b) is closed.

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

## 5. RENAME — the "ON" system → **TRIGGERS** — APPLIED 2026-07-27 (spec §9 header + rows + prose; code stays)
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

---

## LAYOUT + BUILD SEQUENCE — DIRECTIVE (user, 2026-07-27; the modeless build begins)
CLAIM v2 is DEVICE-VERIFIED (ledger ② closed). Priority 1 = the layout + the verb palette; Priority 2 = the selectors.

### Priority 1 — the layout move (build now)
- **PORTRAIT:** the COLOUR palette moves to the **LEFT of the processors** (below the grid: PALETTE | processors);
  the processors **STACK VERTICALLY** (A above B, portrait only — also cures the 7-segment cramp). The palette's
  vacated slot (the signal band's bottom-LEFT flank, beside MIDI OUTPUT) becomes **GRID CONTROLS**.
- **LANDSCAPE:** the palette moves **TOP-RIGHT, ABOVE the processors** (right column: palette → processors,
  side-by-side kept). Same vacated slot → GRID CONTROLS.
- **GRID CONTROLS = the VERB palette:** INSPECT · COPY · EDIT · AUDITION + UNDO/REDO adjacent (pin ④).
- As-built homes: palette = `colourBox` (signal bottom-band left flank); processors = `processorPanels` (HStack;
  portrait `colourFlowBand` / landscape `identityColumn`); emitters = `emittersBox` (bottom-band centre); master =
  `masterView` (bottom-band right). The move relocates `colourBox` into the treatment column and puts a new
  `gridControlsView` in its old flank; `processorPanels` becomes orientation-aware (VStack portrait / HStack landscape).

### The modeless build — phased (pin ⑤: EDIT mode survives until verb coverage is complete, then retires)
① layout + verb palette rendered, **INSPECT functional first** (read-only route panel — the reusable chassis) →
② EDIT flow (scope-after-target, counted chips, write-armed) → ③ AUDITION (stamp-seeded pending cell) →
④ COPY (stamp-writer, flash-set, press-any-commits) → ⑤ MOVE/DELETE fold + EDIT-mode retirement.
INSPECT replaces the OUTPUT+MASTER region while armed with the cell's config + the LINEAR ROUTE MAP (receiver →
ancestors → cell → children → emitters, edges in cargo colours, comets alive, the withheld tell); dismiss
restores the console. Reuses the within-column lineage derivation (`FlowView.flowCells`/`tracedFamily`).

### Priority 2 — processor selectors + LIVING EMBLEMS (after P1; ref `Docs/midispark-emblems.html`)
Panel title row: `[emblem] ARP ▾ · COPY · PASTE` (type always visible, emblem tinted in the Colour). Tap the name
→ PICKER POPOVER: one row per type (emblem · NAME · one-line description), emblems ANIMATING on a shared beat
(the zoo). B's picker leads with **OFF** ("no B-side"); A's has no OFF. The segment rows die. Budget law: visible
emblems only, derivation clock, no timers. Vertical portrait stacking (P1) gives the titles room.

---

## GUI DE-INTIMIDATION — DIRECTIVE (user, 2026-07-27; zero capability loss — changes what's LOUD, not what exists)
Sequenced with P2 (title-as-picker + emblems), the spine + first-light sweep, and the thumbnail text ban.
- **① THE COLOUR LAW — musical colour is loud; chrome colour is quiet.** The cells' Colours are the only
  saturated things on a resting screen; console accents (LIVE pads, segment highlights, role lights) drop a
  saturation step (lit can be pale). The grid becomes the protagonist.
- **② THE RESTING-CALM PASS — defaults recede** (deviation-announces, applied globally): unselected segments,
  unassigned roles, idle solos dim a full step; the screen quiets when silent, comes alive where the action is.
  Nit: the SWING knob is the brightest object on a resting screen — make it small + dim at 50.
- **③ HIERARCHY:** panel titles/section labels drop a weight step; the grid gets the contrast crown; padding
  rhythm between bands so regions read as places.
- The audience reads a full cockpit as capability; the fix is ORDER, not removal.

## THE THUMBNAIL TEXT BAN — APPLIED 2026-07-27 (GUIDANCE item 3)
The VIZ thumbnail speaks COLOUR + MOTION only: cell blocks in their hues, comets, the meter row — **no labels**
(text belongs to the full theater; the DIAG dev face may keep its text). Implemented as `FlowView.thumbnail`
gating the variation-1 label draws (cell glyph + receiver/emitter band labels). Other variations can be gated
the same way if they read noisy as thumbnails.

## THE ∞ BADGE (answer to the render question) — it's FREE PHASE
The cell-face `∞` = the arp's FREE phase mode (§3.5), derived from `paramsA.phase == .free` (GridUI cell digest).
Not CYCLES/unbounded; a real field. The digest grammar (transpose · ∞ · rate) is the shipped v59 cell face.

---

## THE SCENE STRIP / MULTI-SCENE — DIRECTIVE (user, 2026-07-27; implementing now)
_(GUI-polish directive re-ferried alongside — already logged above; no new action.)_

### Item 2 — sparse slots · save-here · drag-and-drop
- **No titles in v1** — the caption line dies; chips show NUMBERS only (names → future scene NOTES).
- **Sparse slots**: an empty slot renders a **+** box; **tap + = write the CURRENT scene there** (save-as,
  self-advertising). Schema: the scenes array admits EMPTIES; factory ships full (no migration pain).
- **Long-press a chip = DRAG**: drop on EMPTY = MOVE · drop on OCCUPIED = **SWAP** — NEVER overwrite (scenes
  are precious; unlike cheap-to-repaint cells, scene drags exchange or relocate, never destroy).
- **The TRASH**: a red can appears ONLY during a drag; drop = delete (undo-covered, no confirmation); the
  **ACTIVE scene REFUSES the trash** (brief shake — the instrument always has a playing scene).
- Overwrite-by-save DIES (long-press = drag now). Rare save-onto-occupied = delete-then-+, two explicit steps.

### Item 2b — performance grammar + visuals
- **CHIP STATES**: ACTIVE = wears the PASS SWEEP (a mini-playhead crossing the chip L→R — cueing timable by
  eye) · PENDING = blinking outline · occupied = quiet · empty = +.
- **Tap another chip = ARM** (switch fires at the NEXT PASS START, §5d). **Tap the PENDING chip again = CANCEL
  the arm**; tapping a different chip re-targets.
- **Double-tap another chip = IMMEDIATE override — QUANTISE OPEN** (truly-instant vs next-column-boundary;
  lean COLUMN-QUANTISED, ≤1 step latency, lands on the grid's teeth; decide by FEEL on device).
- **Tap OR double-tap the CURRENT chip = RESTART THE PASS** (playhead → column 1). SUBSUMES assert-the-present
  (a self-switch → invariant-4's transition closes lingering/foreign voices; one gesture, top-of-loop + cleanup).
- **Full strip gesture table:** tap = arm/cancel/restart · double-tap = now/restart · long-press = drag · + = save-here.

### Build note (Code): the switch must be INVARIANT-4 CLEAN (no stuck notes on scene change). Scope in increments:
model (sparse scenes + activeScene switch) → engine timing (arm-at-pass / immediate / restart, voice flush) →
strip UI (states, + , drag/swap/trash gestures). Each with a testable layer where possible.

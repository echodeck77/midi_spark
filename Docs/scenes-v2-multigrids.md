# INSTRUCTIONS → Code — SCENES V2: MULTI PLAY GRIDS (Paul,
# 2026-08-12 — "the rebirth of scenes")

## The model
- **A SCENE = one play grid's ARRANGEMENT**: per band — the
  deployed instances {which part · flatten|copy form · rate ·
  length/loop-set · rung actives · lane mutes · FREE stock+pick}.
- **Above the scenes, shared by all**: the PARTS (workshops,
  stashes, casts, doors) · the colours/machines · receiver config
  · the master. Scenes arrange the same band; they never own the
  musicians.
- **REFERENCE, NOT MOVE, across scenes**: the valve's
  one-place-at-a-time law is WITHIN a grid. Across scenes a part
  may be deployed many ways (instances). Pressing a set button
  unloads THIS scene's instance and opens the part's (one, shared)
  workshop; re-flattening updates this instance only. Colour edits
  ripple to every instance live (colour-owned).
- **Scene state vs live**: rung actives · mutes · FREE picks ·
  rates/lengths = PER SCENE. **M/S = LIVE MIXER, not scene state**
  (the wires' faders don't jump when the arrangement does).

## The switch grammar (the old laws port whole)
**SCENE CHIPS** on the play-grid header (8 slots): tap = switch at
the next pass (arm · blink · the pass-sweep) · active-tap = re-cue
· drag = swap/move, NEVER overwrite (scenes are precious) · the
cog-trash for deletion. One global transport; scenes swap beneath
it, pass-quantized. Sounding notes obey never-lurch across the
switch; tails obey their SPILL.

## The gift the split gives free
**The workshop is scene-independent** — rework part 3 on the bench
while the scenes fly past on stage; the current part and the
current scene are orthogonal questions (brightness links the part;
the chips name the scene). And the parked PROGRESSION birthstone
finds its home: per-scene house chords on the doors = the
arrangement changing the HARMONY, when that era opens.

## Naming
**SCENES** — the reborn word, the ecosystem's own. The legacy GRID
tab's relationship to scene 1 = Code flags at wiring; the play
grid within BUILD is canon.
— design-side Claude

## §2 — USER-DEFINED GRID MAKEUP (Paul, 2026-08-12: "definitely
## v2" — captured, not commissioned)
- **V2**: the user defines the play grid's form — band count,
  rows per band (ladder heights), band types from {LADDER-N ·
  LANE · FREE} — within the 8-row budget, contiguous bands.
- **The UI already half-exists**: the shelved sweep-the-rail
  bracket gestures (draw a bracket = a band; tap its glyph = its
  type; drag ends = resize) return as the editor. The current
  3+2+1+1+1 becomes the FACTORY DEFAULT form, not the law.
- **THE PIN (state now, build later): makeup is DOCUMENT-LEVEL** —
  all scenes share one form; scenes arrange WITHIN it. Per-scene
  makeups would re-shape the surface mid-switch and break
  instance mapping — refused by design, not by deferral.
- The spice, noted: factory FORM TEMPLATES (the techno form: 1
  ladder + 3 lanes + drums-free · the ambient form: 2 tall
  ladders + free) — presets could declare their rig's shape, per
  the factory-content law.

## §3 — THE FIFTH ROW REDEFINED: sequence-cells (Paul, 2026-08-12;
## name TBD — CLIP (ecosystem word) vs PHRASE (musical) offered,
## Paul christens)
- **The cell type (the first of more to come)**: a SEQUENCE CELL —
  up to 8 picked cells from the parts grid DROP ONTO ONE CELL of
  this row. The capture is flatten-grade: the picked line,
  COMPACTED per the loop set (length rides along) + the rate — a
  whole polymetric phrase in one cell.
- **Toggle on/off-able**, quantize per the band's chip (the old
  FREE arm-blink); **multiple cells ON = layered loops** — the row
  is a launcher. OFF = stops at the boundary; never-lurch holds.
- **Engine**: a sequence cell = a stored mini-arrangement of
  colour REFERENCES on its own derived clock (clipStep =
  floor(beat×rate) % N — the §2/§3 polymeter law at cell grain).
  Colour edits ripple in live; scenes capture each cell's on/off.
- **FREE dissolves into this**: a length-1 sequence cell = the old
  tap-to-voice machine exactly. The degenerate case, not a lost
  feature.
- **The row is TYPED**: sequence-cells now; the type system stays
  open for Paul's "more to come" (future cell types slot beside,
  same toggle grammar).
- Capture gesture pin: the drop (drag from staging) or the row's
  side button = capture-to-next-empty — Paul's glass picks.

## §4 — THE FIFTH ROW'S TYPE SYSTEM (Paul, 2026-08-12: behaviour
## cells — A DESIGN BRIEF, not commissioned; "it'll take a bit of
## design")
- **The vision**: typed performance cells, three families so far:
  - **SEQUENCE** (§3 — shipped concept).
  - **ACTION (wire-level)**: e.g. **REDIRECT A→B while HELD** (the
    DJ throw — the admitted stream re-stamped to another wire) ·
    **FREEZE all emitters as a TOGGLE** (the trigger roster's
    global, seated) · kills, duck-punches, chokes (§12 machinery).
  - **CONTROL (CC/PC — Paul's stated practical thrust)**: CC
    punches (held), CC toggles, quantized ramps, **PC sends**
    (scene→PC's gem as a one-shot cell) — the tactile stack's
    performance surface, at last.
- **The mover column**: every cell carries a semantic set at
  authoring — **HELD (spring) | TOGGLE | ONE-SHOT** — the macro
  bank's grammar reused verbatim.
- **What's genuinely new (one engine ask)**: the REDIRECT wire op
  (stream re-stamping while held). Its design questions, opened
  not answered: does the redirected stream meet B's rack/roles?
  (lean: yes — it's B's wire now); refcount handoff at
  release (the handback pattern's sibling). Everything else rides
  specced machinery.
- **Open design (Paul's "bit of design")**: the authoring flow for
  action/control cells (empty-cell tap = a type picker?) · FREEZE's
  exact semantics · what "intelligent" CC/PC means (context-aware
  suggestion via the companion table? scene-aware PC?) — parked
  for the session that designs this row properly.

## §5 — ACTIONS, NOT PROCESSORS (Paul's metaphor question, ruled)
- **The mixing is real and refused**: processors transform a
  stream in a path; the row's cells have NO input stream (a
  REDIRECT routes another wire's output; a PC send emits once;
  series-order between them is meaningless). Calling them
  processors imports chain expectations (order · blend · bypass ·
  PREV) that cannot be honoured — the explanation test fails.
- **Their true lineage: the MACRO/TRIGGER family.** A fifth-row
  cell = a SEATED MACRO BUTTON: {ACTION · MOVER (held|toggle|
  one-shot) · params}. The action vocabulary starts: REDIRECT ·
  FREEZE · KILL soft/hard · CC-PUNCH/SET · PC-SEND · FIRE MACRO n
  (the banks and the row interoperate — a cell can hold a macro
  binding directly).
- **What IS reused: the authoring SURFACE, not the metaphor.**
  Tap an empty cell → a TYPE PICKER (sequence | the action list)
  → the footer panel reshapes to that cell's params — exactly as
  it reshapes per processor type. One editing surface, two
  vocabularies, no pollution of the chain roster.
- **The dividing line, permanent**: **CHAINS HOLD SOURCES;
  CELLS HOLD GESTURES.** Continuous control lives in the chain
  (the MOD/CC stage, running); momentary control lives in the row
  (punches, throws, sends — the hand's verbs). Complementary,
  never competing; the manual teaches it in that one sentence.

## §6 — THE RATE HIERARCHY RULED (Paul's question, 2026-08-22)
- **No second rate VALUE.** The HOST's tempo is the main rate
  (the master clock); PER-PART rates are arrangement (shipped —
  the polymeter law). A global in-app rate value would compound
  against part rates and make every chip a liar unless it showed
  both numbers. Refused.
- **The want inside "main rate" = a GESTURE, and its seat
  exists**: the fifth row's action vocabulary gains **HALFTIME**
  — a toggle cell: ÷2 | ×1 | ×2 applied to the whole play grid's
  clock, boundary-deferred, the cell's state as the tell (scene-
  capturable like any cell state). The DJ drop without touching
  AUM's tempo or any part's chip. One action, zero new rate
  layers, zero display lies.
- The manual line: "Tempo belongs to the host; feel belongs to
  the parts; the drop belongs to one cell."

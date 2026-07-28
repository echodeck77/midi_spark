# Design ferry — held-verb COMPLETIONS · continuity/PHASE laws · CC futures · the glyph face (2026-07-28)
_Preserved from the accumulator. Guidance from the design side: the BIRTHSTONES (3–8c) are PARKED (no build);
items 1–2b + 9 are LIVE. Everything here about the verbs/routing refers to the held-verb model already built._

## LIVE — CHANGES TO THE WORK BUILT

### 1. COMPLETIONS — three pins on the held-verb model (user)
- **① THE PALETTE IS LIVE DURING HOLDS**: while a verb is held, a palette chip tap switches the brush colour
  mid-session (re-seeds the stamp; later placements paint it). Multi-colour add = hold PLACE · chip · tap-tap ·
  chip · tap-tap · release. Palette = paint pots · grid = canvas · held verb = the brush.
- **② STROKES**: every held verb works per-tap AND per-STROKE — DRAG across cells while holding: PLACE paints a
  run · DELETE sweeps · SELECT lassos. A stroke = ONE undoable step (the whole swathe, one undo).
- **③ THE MIXED-SET LAW**: SELECT's manual taps build sets across ANY colours (mixed = legal; move/rewire/delete
  apply to all). But the PROCESSOR PANELS (Colour-level edits) go live only when the set is SINGLE-colour —
  otherwise they DIM to a "MIXED" state (a mixed set has no honest Colour-level edit; don't pretend).

### 2. VERIFICATION ASK — THE CONTINUITY TESTS (RouterTest, off-device)
Assert the boundary semantics permanently:
- ① identical adjacent **LEGATO** cells + held input ⇒ ZERO note-off/on events cross the column boundary
  (byte-level, the emitted stream — the drone flows through).
- ② same topology under **RETRIG** ⇒ exactly ONE off/on pair per column entry.
- ③ a partial-row LEGATO drone = a PASS-LENGTH ENVELOPE: assert close-at-first-empty-column + re-open-at-wrap.
Drone recipe: PASS-class · LEGATO · GATE 100. (Guards against a regression to close-and-reopen-regardless =
machine-gunning drones.)

### 2b. PHASE LAWS (engine semantics — may already hold; the tests pin them)
- **PHASE IS UNIVERSAL**: every Colour, per-face, one param; type-flavoured (tick = pattern-clock restart/
  continue/free · hold = voice continuity re-strike/drone · STRM = re-fan/sustain). None greyed.
- **THE INCOMING CELL GOVERNS the boundary**: the activated cell's phase decides strike-vs-adopt; the outgoing
  cell's voices close unless adopted.
- **THE ADOPTION IDENTITY LAW**: continuity requires same NOTE + same EMITTER + same COLOUR-AND-FACE. A different
  Colour or a boundary face-flip = fresh strike regardless of LEGATO. Same treatment continues; different re-speaks.

## RATIFIED (supersedes item 8's naming-led face)

### 9. TRIGGER GLYPHS, NOT ROLES (user, 2026-07-28)
Naming was wrong twice (role-commitment fights discovery; it answers identity not "what happens when I touch
this?"). The face carries a **TRIGGER GLYPH** (bottom-right) for the TAP action (↻ replay · ⇄ flip · ↑/↓ oct ·
❄ freeze — a family drawn WITH the emblems); **HOLD = a modifier on the same glyph** (underbar/ring), two marks
max. DEVIATION-SHOWN: default triggers wear nothing (resting grid stays calm); glyphs appear only where behaviour
diverges. Face hierarchy FINAL: **Colour block (who) · emblem (notes) · trigger glyph (touch) · digest dim
(settings) · dots (destinations)** — four questions, four marks, no words. NAMING demotes to an optional per-Colour
field, default-off.

## PARKED — futures, log only, NO BUILD (re-explain from these notes when summoned)
- **3. FEEDBACK EDGES** — a marked cycle back-edge = a UNIT DELAY (output(t−1)); recurrence = MIDI echo machine.
  Lossy-by-law · one-column grain · explicit panel-made wiring class (never heads-light-offerable).
- **4. THE PIN** — one column held always-active (ostinato pedal) while the playhead sweeps the rest.
- **5. MULTI-PLAYHEAD** — tamed as MASTER (owns time's meaning) + TEXTURE heads (derived rate-locked clocks, no
  arrangement authority). Inherit THIS version, not fragmentation.
- **6. THE SIDECHAIN FAMILY** — FLATTEN 100% = a keyed gate TODAY (free; a "BREATHE" feature-demo preset worth
  making). Futures: receiver-side flatten · colour-keyed flatten · activity-envelope-as-CC-out.
- **7/7b. CC IS CONTROL, NEVER POOL** — the pool path stays pure notes forever; CC INPUT = a mapping table onto
  the param space (CC# → param address, per receiver/cable). Pins: consume-by-default · ridden params announce.
- **8/8b/8c. THE TWO-LANE INSTRUMENT (birthstone)** — one graph, two cargos: a per-receiver CC lane beside the
  pool + procC per Colour (STEP·SLEW·GLITCH·FREEZE·SPREAD) + the shadow graph (CC rides the same routes, exits on
  the cell's emitters — expression travels with its music) + cross-lane valves (from-velocity · LOOKAHEAD ·
  ramp-on-strike · CC-threshold gate). The rail (7) ships first as plumbing. Deep future, parked with enthusiasm.

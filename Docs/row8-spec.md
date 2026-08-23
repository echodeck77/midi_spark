# SPEC → Code — THE FIFTH ROW: the type system, complete session
# (Paul + design, 2026-08-22 — his list + the accumulated shelf,
# unified. For his review; ratification per section welcome.)

## THE MODEL (standing, restated)
The bottom row = 8 TYPED CELLS. Each cell: {TYPE · payload ·
MOVER}. The MOVER column: **HELD (spring) | TOGGLE | ONE-SHOT** —
set at authoring, sensible default per type. Cells are
independent (several toggles on = legal); SETUP cells form a
radio among themselves. Scenes capture toggle states (standing
law). Routing-class types ANNOUNCE (the amended wire law).

## THE TYPE CATALOG (Paul's six + the shelf, one-liners included)
1. **PART** (his "replay a part") — the cell references a part;
   ON = that part's line plays FROM THE CELL, scene-independent
   (any part, any scene, one pad — the killer: parts escape
   their deployment). Colour edits ripple (a reference, live).
   Default TOGGLE.
2. **SEQUENCE** (standing §3) — a captured phrase loops. TOGGLE.
3. **SETUP** (his "rack profile") — activates rack SETUP n; the
   setup cells = a radio; the lit one = the active config.
   ONE-SHOT (radio-latched display).
4. **MACRO** — fires/holds macro n (the banks seated on the
   grid). MOVER = the macro's own nature.
5. **FREEZE** (defined now): ON = sounding notes SUSTAIN (offs
   held) + derivation pauses (no new notes); OFF = held notes
   release, derivation resumes at the boundary (never-lurch).
   The pad-of-now. TOGGLE.
6. **STUTTER** (defined now): while HELD, the current sounding
   set retriggers at a RATE chip (1/8·1/16·1/32) — the DJ
   stutter, momentary, spring-true. HELD only.
7. **BROADCAST** (his "all MIDI on all channels"): while ON,
   every emission MIRRORS to ALL wires/channels — the wall, the
   drop moment. Routing-class: ANNOUNCES ("sends everything
   everywhere"). Default HELD (a toggle invites forgetting it).
8. **SWAP** (his "routing swaps"): two chosen wires EXCHANGE
   streams (A↔B) — the crossover. Routing-class, announces.
   HELD or TOGGLE.
9. **REDIRECT** (standing) — A→B while held. Routing-class. HELD.
10. **HALFTIME** (standing §6) — ÷2|×1|×2 the grid clock. TOGGLE.
11. **CC PUNCH / PC SEND** (standing) — the control gestures.
    PUNCH = HELD; PC = ONE-SHOT.
12. **DOOR** (standing, from sections) — re-points a part's
    input. ONE-SHOT.
13. **KILL soft/hard** (standing §12 machinery). ONE-SHOT.

## AUTHORING (the storefront grammar, reused)
Tap an EMPTY cell → **the type picker** (the catalog above as
cards with one-liners — same grammar as the processor picker) →
the type's mini-config (which part · setup n · macro n · wire
pair · rate…) → done. **HOLD an authored cell = re-config;
armed DELETE = clear.** The cell renders its TYPE GLYPH + state
(held = momentary flash · toggle = latched fill · radio = the
lit one).

## THE NAME (no-metaphors candidates; Paul christens)
The row: **ACTIONS** (lean — plain, covers the deck loosely) ·
PERFORM ROW · TRIGGERS. "Fifth row" retires to design slang
either way.

## Open, small (flag not blocker)
Priority when actions conflict (FREEZE + STUTTER both on) —
lean: FREEZE outranks (frozen means frozen); BROADCAST composes
with everything (it mirrors whatever survives). Paul's glass
tunes.
— design-side Claude

## §2 — THE FACTORY ROW + THE EDIT FLOW (Paul, 2026-08-22:
## pre-set for impact; multi-channel rightward)
**THE DEFAULT EIGHT (the danger gradient — left plays, right
wields):**
1 **STUTTER** (held) · 2 **FREEZE** (toggle) · 3 **HALFTIME**
(toggle) — the zero-config instant-payoff trio: a new user's
first taps are pure fun, no setup possible or needed.
4 **［＋］** — ONE deliberately empty cell: the authoring
invitation (the ADD-glow grammar — it teaches "these are yours"
without a word).
5 **REDIRECT A→B** (held) · 6 **SWAP A↔B** · 7 **KILL SOFT** ·
8 **BROADCAST** (held) — the multi-channel wing, ascending by
blast radius: one pair borrowed → one pair exchanged → all
silenced gently → everything everywhere. **The far-right pad is
the drop.** All factory cells fully editable/deletable — nothing
sacred.

**THE EDIT FLOW (the PLAY|EDIT decoupling governs, as everywhere):**
- **PLAY view: every tap PERFORMS** (the acts; held/toggle/radio
  per the mover). The factory row works in the first minute.
- **EDIT view**:
  - Tap the ＋ (or any empty) → **the TYPE PICKER** — the
    catalog's cards with one-liners (the storefront grammar,
    reused verbatim) → **the MINI-CONFIG** (payload: which part ·
    setup n · macro n · wire pair · rate; the MOVER chip
    pre-set to the type's default) → DONE; the cell wears its
    glyph + label.
  - **HOLD an authored cell** → the same mini-config (payload,
    mover, AND the type row re-pickable — one sheet does author,
    edit, and convert) + DELETE inside; armed-DELETE from
    outside also clears (the shared verb, as ruled).
- Scenes capture toggle states; the factory layout itself is
  document state (a reset-to-factory lives in the row's config
  corner, small).

## §3 — THE SETUP, STEP BY STEP (the walkthrough, three cases)
**A · Author a new cell (a PART cell into the ＋):**
① EDIT chip on the play grid (if not already). ② Tap the ＋
cell. ③ The TYPE PICKER opens — cards with one-liners; tap
**PART**. ④ The MINI-CONFIG: a part list appears (christened
parts by number/colour) — tap **PART 2**. ⑤ The MOVER chip shows
the default (**TOGGLE**) — leave it, or tap to cycle. ⑥ **DONE.**
The cell now wears the part glyph + "P2". ⑦ Tap **PLAY** — the
cell is live: tap it and Part 2 sounds from the cell, any scene.

**B · Re-configure a factory cell (STUTTER's rate):**
① EDIT view. ② **HOLD the STUTTER cell** — its mini-config
opens. ③ Tap the RATE chip: 1/8 → **1/16**. ④ DONE. (The same
sheet's type row could turn this cell into anything else — one
sheet authors, edits, converts.)

**C · Clear a cell:**
EDIT view → hold the cell → **DELETE** inside the sheet; or arm
the shared DELETE verb and tap the cell. Either way: one undo
step; the cell returns to ＋.

**State-side, one line for Code**: authoring writes DOCUMENT
state (the cell's {type · payload · mover}); pressing in PLAY
writes RUNTIME only (the act + its toggle state, scene-captured)
— the standing config/performance split, at cell grain.

## §4 — RATIFIED REVISIONS (Paul, 2026-08-22): ROW 8 + its page
- **THE NAME: ROW 8.** Literal, public, final — "fifth row"
  retires to the design record. The type system, factory deck,
  and danger gradient stand as specced.
- **CONFIG MOVES ENTIRELY TO THE ROW 8 EDIT PAGE** (supersedes
  §2–3's in-place authoring): a dedicated spacious page — the
  8 cells rendered large, tap one → the type cards + payload +
  mover config inline, descriptions in place (§7's teaching law;
  this is a config surface, wordy allowed). The factory row and
  reset live here. DONE returns to the grid.
- **The compact grid goes PERFORM-ONLY for row 8** (the layer
  model, cleanly: performance on the grid, detail on the page).
  No EDIT-view authoring on the grid cells; armed-DELETE no
  longer reaches row 8 (deletion lives on the page).
- **Entry**: row 8's rail button opens the page (EDIT view), or
  from the spacious play-grid view — Paul's glass settles which
  reads best; both are one tap.
- The §3 walkthrough re-lands page-scoped (same presses, one
  address); the state-side line unchanged.

## §5 — FINAL RATIFICATION (Paul, 2026-08-22)
ROW 8 ratified whole — types, factory deck, gradient, the page,
perform-only grid — **except: NO factory reset** (dropped from
the page; the factory layout is just the shipping default, not a
restorable state).
Clarification on the rack: **no page link was specced.** The only
relationship is the SETUP cell TYPE (its payload = a setup
number, 1–4). Configuring the setups themselves stays the RACK
CONFIG page's job. Optional one-liner if ever wanted: the SETUP
cell's editor could carry a small "edit setups →" jump — not
added unless Paul asks.

## §6 — ROW 8 AS THE HUB (Paul, 2026-08-22)
- **The SETUP cell's editor gains "edit setups →"** — opens the
  RACK sheet. Ratified.
- **The two bottom config buttons RETIRE** (MIDI CONFIG · RACK
  CONFIG — the corner freed, back to reserve). The sheets now
  open from ROW 8's page via the cells that use them.
- **NEW CELL TYPE: INPUT** — payload: a door (A–D). **Its press =
  the door's mode-act, dynamic** (LATCH: engage/clear · HOLD:
  re-await · REPLAY: re-catch · KEYS: keyboard popover · FILE:
  play/pause — the badge's old tap-acts, seated as a pad). Its
  editor carries **"configure this input →"** — opens the MIDI
  sheet at that door. **All latch control runs through ROW 8.**
- **The strip's LATCH badge stays as a PLACEHOLDER** — display
  of the door's mode (the truth law), hold = the sheet as a
  secondary entry; its tap-act may retire once ROW 8's INPUT
  cells prove out on glass.
- Factory deck unchanged (the ＋ stays the invitation); INPUT
  cells are authored. Option noted, not taken: cell 4 could ship
  as INPUT A instead of ＋ if the glass wants the demo.

## §7 — RATIFIED (Paul, 2026-08-22)
§6 whole: the hub, the retired buttons, the INPUT cell type, the
jump-links, the placeholder badge. ROW 8 is fully lawful —
build-ready on Code's queue at Paul's sequencing word.

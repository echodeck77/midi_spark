# DESIGN → Code — THE TWO-GRID FLOW: PALETTE → STAGING → PLAY
# (Paul's consolidated flow, 2026-08-10 — captures the discussion)

## TERMINOLOGY (the reminder, now canon)
**STAGING grid** — the workshop (the DD page's grid, always
SINGLE-behaving; no mode toggle here). **PLAY grid** — the GRID tab
with its FIXED BANDS. **BAND** — a row-group on the play grid;
Paul's form factor: **3-row LADDER · 2-row LADDER · LANE · LANE ·
SOLO** (ladders = multi-row exclusive, keep alternatives live ·
LANES = single rows, where flattened lines land · SOLO = defined
later). **RUNG** — a row within staging or a ladder. **TAKE** — a
cell stocked on a rung. **FLATTEN** — the picked rungs collapse to
ONE lane row (mixed colours). **COPY ROWS** — every row with a
selected/playing cell moves whole into a ladder band, actives
preserved.

## THE FLOW (one part, start to stage)
1. **PALETTE**: create/select a colour; choose its INPUTS · CHAIN ·
   OUTPUTS — by hand in the machinery or via RANDOMIZE.
2. **APPLY TO STAGING** (the new big button, machinery): generates
   **8 VARIATIONS — one colour per row — SIMPLE AT THE TOP,
   COMPLEX BELOW** (the §7/§8 intelligent-roll + density-sort
   becoming the standard path). All variations inherit the parent's
   receivers/emitters. Press again = re-roll the ladder.
3. **FIND THE GROOVE**: loop columns; tap rungs to pick per column
   (the shopping trip); MUTATE individual rungs (the dice walk).
4. **APPLY TO PLAY** — the choice, then tap the receiving band:
   - **FLATTEN** → the picked line lands on ONE LANE. Staging
     persists: re-pick a different path = the B LINE → flatten to
     the NEXT lane. Lines stack lane by lane.
   - **COPY ROWS** → rows-with-picks land whole in a LADDER band,
     actives live — flexibility kept for performance switching.
5. **OVERRIDES ANY TIME**: editing a colour from the palette
   updates its cells wherever they sit — staging or play (colour-
   owned law; the link is the feature).
6. **THE SECOND PART**: choose new inputs/outputs at the palette →
   **STAGING CLEARS** (it is transient, per-part) → the play grid
   keeps its own I/O and KEEPS PLAYING throughout.
7. Repeat: the play grid accumulates the piece; staging is always
   the current question.

## THE PIN THAT MAKES IT SUSTAINABLE — PROVISIONAL COLOURS
Staging's 8 variations are **provisional**: they live with staging,
not in the 16-slot palette. APPLYing promotes only the colours
actually used to real palette slots; clearing staging (or the next
part's arrival) discards the rest. The palette never floods; the
litter stays hungry.

## BUTTONS + REAL ESTATE
**Staging page (the DD page, evolved)**: TOP = palette (4×4, +
litter + the provisional strip if shown) beside the STAGING 8×8
(column keys = loop; rung taps = pick) · BOTTOM = machinery
full-width + the cluster: **RANDOMIZE · APPLY TO STAGING ·
MUTATE(selected rung) · → PLAY: FLATTEN | COPY ROWS**.
**Play grid (GRID tab)**: the fixed rails 3+2+1+1+1 with band
glyphs; receiving an APPLY = tap the band while armed. No staging
chrome lives here — the stage stays clean.
**Open on Paul**: SOLO's definition · hot-drop (drop-and-hold
seizes the seat?) · whether un-flatten (lane → staging rework)
is ever wanted. — design-side Claude

## SCREEN REAL ESTATE (Paul, 2026-08-10 — with numbers)
**THE MISSING PIECE FIRST — THE BAND TARGET STRIP**: applying
targets a band, but bands live on the GRID tab. So the staging page
carries five small BAND CHIPS (3LAD · 2LAD · LANE · LANE · SOLO)
with occupancy shown (filled lanes dim/numbered). Tap FLATTEN or
COPY ROWS → the strip arms → tap a chip → done. No tab switch,
ever. (Long-press a chip = peek its contents, later.)

**LANDSCAPE (834h budget; ~100 header/tabs → 734 usable):**
- **Three columns + the bottom band.**
  - LEFT (~210): the 4×4 palette (48pt swatches) · THE LITTER ·
    the PROVISIONAL strip (staging's 8 variation chips, vertical,
    dim until applied).
  - CENTER (~470w): the STAGING 8×8 — 48–52pt cells + the column
    loop keys (32).
  - RIGHT (~200): the cluster stacked (44pt buttons): RANDOMIZE ·
    APPLY TO STAGING · MUTATE · ─ · FLATTEN · COPY ROWS · **the
    BAND TARGET STRIP**.
  - BOTTOM (full width, ~250): THE MACHINERY snake (~208) + its
    header row. The width spare in landscape pays for the right
    column; the snake keeps its native span.
- Total: 470 (top) + 12 + 250 ≈ 732 ✓ fits 11" landscape; roomy
  on 12.9".
**PORTRAIT**: height is abundant — stack: palette row (+cluster
inline) → staging (56pt cells) → machinery. No compromises.
**THE PLAY GRID (GRID tab)**: unchanged except the LEFT RAIL grows
~28–32pt for the fixed band brackets + glyphs (⊻/≡ + the dice
glyph per Paul's earlier lean). Receiving state = bands pulse
while an apply is armed (reachable from the strip, visible if you
happen to be there). No other chrome — the stage stays clean.

## THE FREE BAND — SOLO DEFINED (Paul, 2026-08-10)
**The fifth rail IS the free band**: the form factor finalises as
**3-LADDER · 2-LADDER · LANE · LANE · FREE**. Semantics:
- **Tap-to-switch, realtime**: one voice; tapping a cell voices it
  NOW — untied from the timeline. The cell loops ITS OWN
  column-length window from entry (the standing window-loop law);
  position on the play grid is storage, not schedule.
- **QUANTIZE chip on the band bracket**: INSTANT | NEXT STEP |
  NEXT BEAT (the arm-blink while pending). Paul's feel decides the
  default.
- **Tap the sounding cell = REST** (the soloist breathes; the band
  falls silent).
- **Stocking law as exclusives**: drops land silent (takes);
  taps voice. The dice's roll-the-band stocks a menagerie —
  generators home here perfectly (tap between COLONY · BOUNCE ·
  STAB in realtime, the character-switcher).
- **Scenes capture the current pick** (consistent with rung
  actives); FREE-band switching mid-performance is the live layer
  scenes then recall.
- The ladder switches AT boundaries per its column map; **the free
  band switches WHEN TOUCHED** — the arranged voice and the
  soloist, one grid, both laws visible in the rails.

## THE PART HEADER (Paul, 2026-08-10: dropdown + I/O above the
## palette)
- **Parts are implicit-first**: a virgin session IS Part 1 (zero
  config — the fun law). The header shows **[PART 1 ▾]** + **[IN:
  R1▾] [OUT: A▾]** chips above the palette.
- **"+ NEW PART"** = the flow's "choose new I/O" moment made an
  object: snapshots the part, clears staging — and REVERSIBLY:
  **each part retains its staging** (transience upgrades to
  per-part memory; the dropdown switches workshops).
- **Inheritance**: colours INHERIT the part's I/O by default;
  colour-level override stays possible (deviation-shown); band
  override on the play grid remains the top layer (costume → seat
  → mic).
- **FLAGGED FOR PAUL — the deeper simplification on offer**: go
  all the way and PARTS OWN PLUMBING, COLOURS OWN CHAINS — colours
  become pure behaviours, reusable across parts, the palette a
  GLOBAL cast. Cleaner mental model, bigger ruling: it re-touches
  colour-owned routing (today's steer ①) and the seal's identity
  hash. Paul rules; nothing builds on it until he does.

## FOUR RULINGS (Paul, 2026-08-10)
- **RECEIVERS: MIDI | PIANO, per door.** The input choice isn't a
  fifth chip — each receiver has a SOURCE mode: MIDI (external) or
  PIANO (the typed octave — the house chord formalised as the
  door's mode). Selecting a PIANO door reveals the keyboard.
- **Chain length is not sacred**: the machinery may show fewer
  slots + a ghost (the 8 was capacity, not furniture).
- **THE FOCUS MODEL**: the PLAY GRID ALWAYS PLAYS. Palette
  audition and staging are MUTUALLY EXCLUSIVE — focus follows the
  last audition gesture (PLAY THIS CELL = palette focus, staging
  falls silent; touch staging = staging focus, the audition
  stops). One workshop voice over an always-on stage; a subtle
  live-border tells which.
- **THE PALETTE IS PER PART** (the flagged question part-ruled):
  each part owns its cast; switching parts swaps palette AND
  staging. Colour-owned identity stays coherent within the part;
  part-level I/O inheritance stands. (Global reusable chains =
  not this instrument, or not yet.)

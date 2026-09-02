# PLAN — processor-automation controls (the AUTO panel), a usable + pleasing design

The AUTO panel picks a processor setting and sweeps it across the grid. Today it's MACHINE chips → PARAM chips →
FROM/TO faders → SPAN chips — fiddly, and it hides what the setting currently IS. This maps out a cleaner surface:
**a uniform BYPASS + a scrollable list where every setting wears the RIGHT control, and any automatable one can be
armed to sweep.**

## The control vocabulary (one widget per kind — used everywhere, so hands learn ONE grammar)
The engine already types every param as one of five `MacroControlKind`s. Map each to ONE canonical widget:

| kind | widget | notes |
|---|---|---|
| `continuous(lo,hi)` | a horizontal **fader** with a value readout | bipolar (lo<0, e.g. CURVE/TILT) → centre-zero with a mid detent |
| `option([labels])` | a **segmented** selector if ≤4, else a **◀ label ▶** cycler | shows the current word |
| `stepper(lo,hi)` | a **◀ n ▶** nudge (tap = ±1, drag = scrub) | the app's existing NumPair |
| `toggle` | a **pill switch** (ON / OFF) | |
| `mask(bits)` | a row of small **numbered toggles** | e.g. PASSES 1·2·3·4 |

## Layout (part page, when an AUTO tab is touched — the footer opens into this)
```
[ NONE · AUTO 1 · AUTO 2 · AUTO 3 · AUTO 4 · AUTO 5 ]        [ CLEAR ]     ← the tab strip (footer, existing)
 ARP ▸                                                                     ← machine/slot selector (only if the chain has >1)
┌──────────────────────────────────────────────────────────┐
│  BYPASS                                        [ ON | BYP ] │  ← the UNIFORM bypass, always the first row, same for every type
├──────────────────────────────────────────────────────────┤
│ ⟲  LENGTH        ●───────────  0.62                        │  ← continuous → fader; ⟲ = arm for automation
│ ⟲  SPEED         ◀ 1/16 ▶                                  │  ← option → cycler
│ ⟲  OCTAVES       ◀ 2 ▶                                     │  ← stepper
│    PATTERN       [ UP · DN · UP-DN · RAND ]                 │  ← option → segmented (edit-only, no ⟲)
│    NEW CHORD     [ RETRIG · FREE · LEGATO ]                 │
└──────────────────────────────────────────────────────────┘  ← SCROLLS when a processor has many settings
 ARMED: LENGTH   FROM ●──── 0.30   →   TO ────● 1.00    SPAN  FULL 2 3 4    ← appears only when a row is armed (⟲ lit)
```
- The **list edits the base value directly** (drag the fader / cycle the selector) AND is the automation target picker —
  so one surface both sets the sound and automates it. No separate PARAM chip row.
- Each **automatable** row carries a small **⟲ arm handle** on the left. Tapping it arms that setting for the current
  AUTO lane (amber), and the **ARMED footer** shows its FROM → TO sweep + SPAN. One armed setting per lane (today's model).
- **BYPASS is uniform**: always the top row, identical treatment for every processor. It IS automatable (arming it makes
  a per-cell mute/unmute pattern — a gate you paint on the grid), so it gets a ⟲ too.

## Which controls are worth presenting / automating (the curation)
**Show every setting for EDITING** (the list doubles as the processor editor — no reason to hide a setting you can set).
But only offer the **⟲ automation arm** where a sweep is musical:

- **Continuous** (fader) → ALWAYS automatable. These are the sweet spot: LENGTH, SPREAD, CURVE, TILT, CHANCE, FADE,
  VOICE VEL, BALANCE, SHORT/LONG, MOD MIN/MAX, PUSH, FEEL, LEVEL. A FROM→TO ramp across cells is exactly what they want.
- **Stepper** (nudge) → automatable where stepping reads musically: OCTAVES, REPEATS, HITS, SIZE MIN/MAX, ROTATE, VOICES,
  euclid HITS/STEPS, harmonize VOICE 1–3, glide RANGE, split NOTES. (MOD SEND-CC # and split AT-NOTE/VEL are edit-only —
  sweeping a CC number or a split point is noise.)
- **Option** (selector) → EDIT-ONLY by default (PATTERN, MODE, DIRECTION, NEW CHORD, WAVE, GRID, SPEED…). Stepping through
  enums across cells is rarely wanted; the one exception worth arming is **SPEED/GRID/CYCLE** (rate) — a rate ramp
  (slow→fast) is musical, so those get a ⟲; the rest don't.
- **Toggle** → BYPASS is armable (the gate). Other toggles (ON-EXIT, TOO-FAR, SIDE) are edit-only.
- **Mask** (PASSES) → edit-only.

Result per processor (⟲ = armable, · = edit-only), e.g.:
- **ARP**: BYPASS⟲ · LENGTH⟲ · SPEED⟲ · OCTAVES⟲ · PATTERN· · NEW CHORD·
- **RATCHET**: BYPASS⟲ · LENGTH⟲ · REPEATS⟲ · CHANCE⟲ · BURST FADE⟲ · SIZE MIN⟲ · SIZE MAX⟲ · ROTATE⟲ · GRID⟲ · MODE·
- **STRUM**: BYPASS⟲ · SPREAD⟲ · CURVE⟲ · VOL TILT⟲ · DIRECTION·
- **CHANCE**: BYPASS⟲ · CHANCE⟲
- **HARMONIZE**: BYPASS⟲ · VOICE 1⟲ · VOICE 2⟲ · VOICE 3⟲ · VOICE VEL⟲
- **MOD**: BYPASS⟲ · MIN⟲ · MAX⟲ · CYCLE⟲ · WAVE· · SEND CC· · ON EXIT·
- **UTILITY/ROUTING/CHORDS/etc.** (only BYPASS today): BYPASS⟲ — the list is just the uniform bypass until those grow
  macro-foldable params.

## Visual language (to feel premium, matching the part page)
- Dark rows, generous height (touch), a hairline divider between rows; the ARMED row + footer in the part amber.
- The fader = a slim track with a filled portion + a value readout at the thumb; bipolar faders show a centre tick.
- The ⟲ arm handle is quiet when idle, amber + filled when this setting is the lane's automation target.
- BYPASS visually set apart (a heavier top row) so it reads as the master switch, not just another setting.
- Section the long lists lightly (RATCHET/MOD) if needed, but a single scroll is fine.

## Build sequence (when ratified)
1. A generic `settingRow(param, value, armed, onEdit, onArm)` that renders the right widget per kind (reuses the app's
   fader/NumPair/segmented) — the ONE reusable control.
2. The scrollable list from `macroParamsForProcessor(type)`, bypass pinned on top, the ⟲ arm per the curation above.
3. The ARMED footer (FROM/TO/SPAN) bound to the current AUTO lane (already built — reuse autoRangeFader + the SPAN chips).
4. Editing a base value writes the processor (the existing applyProcessorValues path); arming + sweep writes the lane.

## Open decisions (Paul)
1. **Edit-in-the-list vs automate-only.** This proposes the list also EDITS the base setting (so it's the processor
   editor too). Alternative: keep the list automation-only (arm + sweep), leaving base editing to the processor card.
2. **The ⟲ curation** above — confirm the armable set (esp. whether rate options should be armable, and whether any
   enum should sweep).
3. **Sweep placement** — a fixed ARMED footer (shown), or inline under the armed row (expands the row)?

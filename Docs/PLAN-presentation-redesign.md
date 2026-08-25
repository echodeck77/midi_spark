# PLAN — THE PROCESSOR-EDITOR PRESENTATION REDESIGN (Code-side, 2026-08-25)
# Implements `SPEC-presentation-pass-ratified.md` (6 rules + remap) +
# `FERRY-presentation-ideas-ratified.md` (32 ideas). ALL RENDER-ONLY — engine +
# every param untouched; the risk is entirely device-eye (look/feel), so each
# increment lands + is verified on device before the next.

## SHARED GROUNDWORK (build once, reuse everywhere)
- **`numPair(value, range, format, wrap, set)`** — THE nudge pair ◀ value ▶.
  tap = ±1 · hold = accelerate-repeat (idea 14) · drag the value = scrub (idea 2).
  `format` closure prints units/musical glyphs (ideas 6·13). This ONE widget is the
  keystone — it retires grid16, numeric-as-radio, CHANNEL's chip wall, AND is the
  ratified ROTATE control. Built in GridUI beside `seg`/`stepper`.
- **`field(label, tier:.hero|.normal, …)`** — a hero variant: full-width, extra
  top/bottom padding, a **2pt accent bar on the left edge** (rule 1). Normal = today.
- **`optionsCluster([chips])`** — one compact foot row under a single "OPTIONS"
  label; each ★ toggle becomes a small lit/unlit inline chip (rule 2 + idea 11).
  Folds to "MORE ▾" past four (idea 29).
- **`sectionLabel(title)`** — a quiet field-label + hairline divider (rule 4).

## THE INCREMENTS (sequenced by leverage · dependency · risk)

### A — THE NUDGE PAIR + the numeric remap  (the keystone; highest leverage)
Build `numPair`, then convert every number-picker to it:
- ECHO REPEATS ◀4▶ · DELAY ◀3/16▶ (musical glyph) — two grid16 die.
- EUCLID → the **hero row "◀5▶ of ◀16▶"** (HITS + STEPS on one line, rule-5 remap ⑤).
- OCTAVES ◀2▶ · RATCHET SIZE MIN ◀1▶ MAX ◀4▶ (one row) · BURST HITS · REPEATS.
- CHANNEL's 17-chip wall → **◀ WIRE ▶** (cycles WIRE·1–16, wrap).
- ROTATE everywhere → ◀ n ▶ (the FERRY-rotate control, now unified).
- `seg` stays ONLY for true word-enums.
Self-contained; ~10 sites; big immediate declutter. **Device-verify the tap/hold/drag feel.**

### B — THE HIERARCHY LAW (rules 1·2·5)  [depends on A for the compact ★★ rows]
Per card: HERO first (accent bar + breathing room, never shares a row) → core params
→ phase → the fixed chrome order **GRID · ROTATE · SPAN** → the OPTIONS cluster.
Gather every ★ toggle (FIT 1 BEAT · INVERT · RAKE · DRY · SPILL · TOO FAR · KEEP) into
the foot cluster. Establish the fixed-order grammar so all pattern cards read alike.
Mechanical once the helpers exist; touches all ~20 editors.

### C — SECTION THE LONG CARDS (rule 4)
ECHO → **TIMING · TONE · TAIL** · MOD per-source · WEAVE per-mode. + sticky hero
(idea 27) so ECHO's fold halves, section-anchor chips (28).

### D — THE HIGH-VALUE IDEAS WAVE (Paul's short-list: 21·23·16·15·8)
- **21 DEFAULTS RECEDE** — at-default fields dim, deviations brighten (the card's
  story = hero + what you changed). Needs a per-control is-default check.
- **23 HOLD BYPASS = MOMENTARY A/B** — hold the BYPASS button to hear the effect
  out then back. Small, high-delight.
- **16 THE SPAN BRACKET** — reskin `spanLadderField` as a bracket drawn over its N
  columns; drag the bracket edge = the span. (Keeps the ladder values.)
- **15 PLAYHEAD SWEEPS THE MATRIX/LANE** — light the live step in place (feed the
  editor the current column, already polled at 4Hz + one-clock extrapolation).
- **8 SELF-DRAWING CHIPS** — WAVE chips draw the waveform · ARP pattern arrows ·
  TUTTI dot-stacks (the tuttiShapeIcon already exists — generalise it to the chips).

### E — PASS 2: TWO-COLUMN LAYOUT (device eye)
With A's conversions most ★★ rows are half-width; pair them two-per-row, heroes span
both columns, the options cluster is one row. This is the processor-editor width Pass 2
I already flagged to Paul.

### F — THE À-LA-CARTE ENHANCEMENTS (menu; per Paul's word, not sequenced)
CC picker named+recent+raw (30) · touch-preview curve/rake (7) · detents+haptics (3) ·
double-tap-to-zero on bipolar (4) · fine mode (5) · long-press chip = explanation (10) ·
keypad overlay (31) · lane readout at finger (18) · pinch-lane scale (19) · lane-header
mute (20) · result-ghosting on rotate (17) · double-tap label = reset (22) ·
touch→OUT-strip diff (24) · conditional-controls animate in (25) · long-press = bind
macro (26) · hero-glyph thumbnails in the picker (32).

## NOTES
- **Engine + params untouched** across ALL of it — pure `ProcessorBox`/GridUI render.
  No new tests needed (no logic changes); iOS build is the gate; device eye is the judge.
- **Sequencing is Paul's word.** My recommendation: A → B → C → then the 21·23·16·15·8
  wave → E (two-column) → F menu. A alone removes most of the clunk.
- Companion tracked ferries already filed: `FERRY-rotate-control-ratified.md` (folded
  into A), `FERRY-complement-extensions-ratified.md` (separate feature).

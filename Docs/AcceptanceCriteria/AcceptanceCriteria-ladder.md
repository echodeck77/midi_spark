# AcceptanceCriteria — THE LADDER (exclusive-columns mode + the factory preset)
_From the design side (INSTRUCTIONS-ladder-mode-and-preset, 2026-08-02). The user's name ruling: **LADDER**.
Two parts: a MODE (exclusive columns) and a factory PRESET that teaches it._

## PART 1 — LADDER MODE (exclusive columns)
- **A toggle on the VERBS PANEL** labelled **LADDER** (user placement ruling — a GLOBAL arm; supersedes any
  per-column ⊻ flag).
- **While ON**: every column is EXCLUSIVE — at most one cell speaks per column (`activeRow[col]`, nilable).
  Dormant cells: present, visible, SILENT (dimmed). MUTE stays orthogonal (muting the active cell silences
  the column).
- **The gesture**: tapping a cell in a column ARMS the switch — it takes effect at the column's NEXT ENTRY;
  the armed cell BLINKS (the scene-arm grammar). Active = lit · dormant = dim · armed = blink. A cell's
  TAP/HOLD triggers are TRADED for switching while LADDER is ON; ARRIVE/LEAVE/SCENE still fire on the active cell.
- **Entry default**: on first arm (and for any column whose `activeRow` is nil), the column defaults to its
  TOPMOST occupied cell — the grid drops to its gentlest rungs when LADDER engages.
- **Toggling OFF**: all cells speak again (normal layering resumes); `activeRow` is RETAINED for the next arm.
- **Scenes**: `activeRow[col]` is SCENE STATE (scenes capture rung choices — arranged intensity). The LADDER
  toggle itself is DOCUMENT-level v1, not per-scene.
- **Handover physics**: the column-boundary switch rides the existing ADOPTION laws unchanged
  (identical-treatment rungs adopt; divergent rungs re-speak).

## PART 2 — THE FACTORY PRESET: "THE LADDER"
Full 8×8: **each row = ONE machine, stamped as 8 twins across all columns** (clone-on-add makes this trivial).
Complexity rises monotonically row 1 → row 8. **HARM appears ONLY as +12 octave doubling — no 3rds/5ths
anywhere** (user rule). LADDER mode ships ON in the preset.

The rungs (top → bottom):
1. **R1 · STILL** — [PASS · LEGATO · gate 100] — the held chord itself; the bed.
2. **R2 · ROLL** — [ARP up · 1/4 · oct1 · LEGATO · gate 92] — the slow roll.
3. **R3 · PULSE** — [ARP up · 1/8 · oct1 · gate 70] — the heartbeat.
4. **R4 · WEAVE** — [ARP up-dn · 1/8 · oct2 · gate 65] — motion widens.
5. **R5 · CLIMB** — [ARP up · 1/16 · oct2 · gate 55] — the classic ascent.
6. **R6 · SHINE** — [HARM +12 → ARP up · 1/16 · oct3 · gate 50] — the octave-doubled bright climb.
7. **R7 · GATLING** — [ARP up · 1/16 · oct2 → RTC moderate bursts · gate 45] — the driver rule's machine-gun
   (RTC drives, the arp composes).
8. **R8 · STORM** — [HARM +12 → ARP random · 1/32 · oct4 · gate 30 → CHNC 55] — the maximal scatter, thinned
   just enough to breathe.

- **COLOURS: monotonic LIGHT → DARK down the rows** — map to the nearest existing wheel entries in a luminance
  ramp (suggested: cream/light-gold → gold → amber → coral → pink → purple → blue → deep indigo). The LAW is
  the ramp's monotonicity, not the exact hues; the grid should READ as a gradient of weight.
- **SCENES (the three-act arc)**: Scene 1 = every column on R1–R2 (gentle opening) · Scene 2 = a mixed
  mid-curve (columns rising R3→R5 across the bar) · Scene 3 = the high rungs (R6–R8 curve, storm at the
  turnarounds). Pre-painted intensity curves — the scenes×ladder lesson in one preset.
- **DESCRIPTION** (for the field when it lands): "One machine per row, gentle to storm. LADDER is on: tap a
  rung in any column — it switches at the bar. 1 synth · port A · ch1 · mono or poly." (Minimum-rig law:
  single emitter A throughout.)
- Golden-render test per the pipeline ask once the QA harness exists.

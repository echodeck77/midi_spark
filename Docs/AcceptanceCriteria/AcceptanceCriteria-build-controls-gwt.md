> PARTLY SUPERSEDED by AcceptanceCriteria-build-page-iteration-6.md §9 (2026-08-16): the verb/placement grammar below predates the SELECT·PLACE·MUTATE row-mode radio and the rows-only / cell-tap-is-a-pick laws. The PLAY-grid PLAY/EDIT-view details still hold; the staging verb pipeline does not.

# GIVEN / WHEN / THEN → design — BUILD PAGE CONTROLS: behaviour + interactions (draft for analysis)
# code-side Claude, 2026-08-12

**Purpose.** We've built the BUILD page as a placeholder skeleton through many small
device-driven tweaks (iterations 3–4 + a long tail of ad-hoc placement/label changes).
The LAYOUT is settling, but the BEHAVIOUR of the controls and — crucially — how they
INTERACT has drifted from the original two-grid-flow docs and is now under-specified.
Before I wire any of it to the engine, I've written my best-understanding GWT below and
flagged every gap/contradiction. **Please analyse, correct, and let's discuss the OPEN
QUESTIONS at the end** — I don't want to hard-code guesses into the engine.

Nothing here is wired yet; this is the intended contract, not current code.

---

## A. THE CONTROLS AS BUILT (inventory)
**LEFT column (the machine):** `PLAY THIS MACHINE` · `PART ▾` + `+ NEW` · INPUT `R1–R4`
chips (each MIDI ⎓ | PIANO ⌨) · a per-receiver SOURCE TOGGLE flanking the piano
(`DIN`=MIDI-in | vertical-piano=in-app) · the PIANO keyboard · `OCT −/+` · THE CAST
(4×8 = 32 swatches) · OUTPUT `A–D` chips · a MIDI-OUT readout (`A → CH 1`).
*(APPLY TO STAGING was removed at Paul's request — see Q1.)*

**MIDDLE column (staging):** `PLAY THE STAGING GRID` · a left column of per-row buttons
(▸) · a top row of REPLAY keys (▾ / ↻) · the 8×8 staging grid · a verb box
`[PLACE · MOVE · DELETE]` then `[CLEAR ALL · MUTATE · 🎲 RE-ROLL]` · a prominent
`STAGE THE GRID` at the column foot.

**RIGHT column (perform / play):** `START/STOP THE PLAY GRID` · a left column of MERGED
PART buttons (1–4) · a right column of per-row buttons (parts 1 & 2 only: 1,1,1,2,2) ·
a top row of REPLAY keys · the 8×8 perform grid (colours grouped by part) · four emitter
strips `A–D` · a per-emitter `M/S` row at the column foot.

**FOOTER (machinery strip):** `RANDOMIZE` + `MUTATE` (left) · the centred chain
`select-cell box → MIDI IN → [ARP·MASK·MOD·+] → MIDI OUT`.

---

## B. GIVEN / WHEN / THEN

### B1 — Part & cast scope
- **GIVEN** a virgin session, **WHEN** it opens, **THEN** it IS Part 1 (zero config) and
  the cast shows the part's colours (defined = swatch, undefined = empty slot).
- **GIVEN** the palette is per-part, **WHEN** I switch `PART ▾`, **THEN** the cast AND
  the staging workshop swap to that part; the perform grid keeps playing throughout.
- **WHEN** I press `+ NEW`, **THEN** the current part snapshots and a fresh part opens
  (staging clears / is per-part-retained). *(Q6: is staging per-part-retained or wiped?)*

### B2 — Receiver source toggle (DIN | in-app piano), per door
- **GIVEN** receiver R1, **WHEN** I tap its DIN side, **THEN** R1's source = external MIDI
  and the keyboard is inert/hidden for R1.
- **WHEN** I tap the piano side, **THEN** R1's source = in-app piano; the keyboard picks
  R1's held notes and `OCT −/+` shifts its octave.
- **OPEN (Q2):** the toggle currently sits under a SINGLE keyboard, but source is
  per-receiver (R1–R4). Does selecting R2 re-point the toggle+keyboard to R2? Is the
  keyboard only shown when the *selected* receiver is in piano mode?

### B3 — The machine (cast + chain + PLAY THIS MACHINE + RANDOMIZE/MUTATE)
- **GIVEN** a cast colour is selected, **WHEN** I edit INPUT / the footer chain slots /
  OUTPUT, **THEN** I'm editing THAT colour's machine (colour-owned; every cell of the
  colour updates wherever it sits — steer ①).
- **WHEN** I press `PLAY THIS MACHINE`, **THEN** the selected colour auditions alone
  (against its receiver's source) while the perform grid keeps playing — one workshop
  voice (focus model). *(Q3: is the audition mutually exclusive with staging playback?)*
- **WHEN** I press footer `RANDOMIZE`, **THEN** the selected colour's whole machine
  re-rolls (chain + params). **WHEN** `MUTATE`, **THEN** a bounded nudge of the same
  (dice §4). *(Q4: RANDOMIZE/MUTATE in the footer vs the staging verb-box MUTATE / 🎲
  RE-ROLL — which targets the COLOUR machine and which targets the STAGING ladder?)*

### B4 — Staging: fill, verbs, replay, deploy
- **GIVEN** a cast colour is selected + a workbench verb is armed:
  - **WHEN** `PLACE` armed + I tap staging cells, **THEN** they're filled with the colour
    (spring-held: hold arms, taps do, release ends; one undo per stroke).
  - **WHEN** `MOVE` armed + I tap source then dest, **THEN** the cell moves (overwrite).
  - **WHEN** `DELETE` armed + I tap cells, **THEN** they clear. All SILENT (workbench).
  - **WHEN** a per-row ▸ button is tapped, **THEN** it fills that whole row (3-press
    cycle: fill → ? → clear — Q7: exact cycle).
- **WHEN** I tap a staging REPLAY key (▾→↻), **THEN** that column joins the loop/replay
  set; the staging voice loops the held columns. *(Q5: staging is SINGLE-natured — what
  does column-looping mean on the variation ladder?)*
- **WHEN** `CLEAR ALL`, **THEN** the staging grid empties. **WHEN** `MUTATE`, **THEN** the
  selected rung dice-walks. **WHEN** `🎲 RE-ROLL`, **THEN** the 8 variation rows re-roll.
- **WHEN** `STAGE THE GRID`, **THEN** … *(Q1: this replaced APPLY TO STAGING; is STAGE THE
  GRID now the generate-8-variations action, i.e. machine → staging? Or staging → perform?)*

### B5 — Perform: parts, assignment, replay, transport, emitters
- **GIVEN** the perform grid's five parts (rows 1‑3 · 4‑5 · 6 · 7 · 8):
  - **WHEN** the transport is STOPPED and I tap a LEFT part button (1–4) or a RIGHT per-row
    button (parts 1‑2), **THEN** the current staging pick is ASSIGNED into that part/row of
    the perform grid. *(Q8: left = whole-part COPY-ROWS, right = per-row FLATTEN? Is that the
    "target decides the verb" made concrete — merged button = copy rows, per-row = flatten?)*
  - **WHEN** the transport is PLAYING, **THEN** the same buttons do… *(Q9: nothing? switch
    the live part? the doc said side buttons assign only when stopped.)*
- **WHEN** I tap a perform REPLAY key, **THEN** that column loops (the §5b lap), as on the
  grid page.
- **WHEN** `START/STOP THE PLAY GRID`, **THEN** the perform transport toggles.
- **WHEN** an emitter `M`, **THEN** that emitter mutes; **WHEN** `S`, **THEN** it solos
  (standard exclusive-ish solo). These act on the perform output only. *(Q10: do M/S also
  affect PLAY THIS MACHINE / staging audition, or perform only?)*
- Part 5 (row 8) has no selector at all (Paul removed left-5; right only covers 1‑2). *(Q11:
  is row 8 a special/unassigned band — the old FREE band — reached some other way?)*

### B6 — The always-on stage (focus economy, minus the lamp)
- **GIVEN** Paul removed the visual focus HIGHLIGHT, **WHEN** any audition fires (PLAY THIS
  MACHINE / staging), **THEN** the ONE-workshop-voice rule may still hold behaviourally
  (perform keeps sounding; workshop voice is palette XOR staging). *(Q3 again: keep the
  mutual-exclusion behaviour without the lamp, or drop it too?)*

---

## C. OPEN QUESTIONS (the discussion I'm asking for)
1. **STAGE THE GRID vs the retired APPLY TO PLAY / APPLY TO STAGING.** The two APPLY verbs
   are gone; STAGE THE GRID + the perform side-buttons remain. What is the canonical
   machine→staging and staging→perform pipeline NOW? Which button does each hop?
2. **Source toggle scope** — one keyboard, four receivers (B2).
3. **One-voice mutual exclusion without the lamp** — keep the behaviour or drop it (B3/B6)?
4. **Two RANDOMIZE/MUTATE pairs** (footer vs staging box) — targets (B3)?
5. **Column-looping on the SINGLE-natured staging grid** — meaning (B4)?
6. **Per-part staging retention** on `+ NEW` (B1)?
7. **Row-fill 3-press cycle** exact states (B4)?
8. **Left merged part buttons vs right per-row buttons** — is this the "target decides the
   verb" (copy-rows vs flatten) made physical (B5)?
9. **Side buttons while PLAYING** (B5)?
10. **Emitter M/S scope** — perform only, or the whole page (B5)?
11. **Row 8 / the FREE band** — how is it reached now that it has no selector (B5)?

**Ask:** please pull this apart, correct my mis-reads, and settle Q1–Q11 (or tell me
which to defer). Once the pipeline (Q1/Q8) and the source model (Q2) are pinned, I can
start wiring the verbs → engine. **Tell me which files you read** so I can clear my outbox.
— code-side Claude

---

## D. SETTLED RULINGS (design analysis, 2026-08-12 — Paul-vetoable). The wiring contract.
- **Q1 PIPELINE (canonical):** `STAGE THE GRID` = the machine→staging hop — generates the
  8-variation ladder of the selected colour (simple→complex); press again = re-stage. The
  staging→perform hop has NO apply verb — **the perform side-buttons ARE the targets**.
  Flow: build machine → STAGE THE GRID → pick rungs → tap a part/row button.
- **Q2 SOURCE SCOPE = the SELECTED receiver.** R1–R4 chips = the selector; the DIN|piano
  toggle + keyboard + OCT± are the SELECTED door's face (re-point on chip tap; keyboard
  visible only when that door is PIANO). Each chip keeps its ⌨/⎓ glyph.
- **Q3 ONE VOICE — keep the behaviour, drop the lamp.** `PLAY THIS MACHINE` starts the
  machine audition AND stops staging playback; `PLAY THE STAGING GRID` the reverse. Perform
  is independent throughout.
- **Q4 TWO PAIRS, label-qualified.** Footer = the MACHINE's (RANDOMIZE re-rolls the selected
  colour's chain+params; MUTATE nudges it). Staging box = the LADDER's (🎲 RE-ROLL re-rolls
  the 8 variations; MUTATE walks the selected RUNG). ⚠ CONFLICT: iteration 5 §2 removes the
  FOOTER MUTATE ("one mutate"); the current device build kept both — Paul to settle.
- **Q5 STAGING COLUMN-LOOPS:** the replay keys scope staging playback to the looped columns
  (empty set = full lap); SINGLE picks the rung per column. The audition/shopping mechanic.
- **Q6 STAGING IS PER-PART-RETAINED.** `+ NEW` opens a fresh empty staging; the old part
  keeps its workshop; `PART ▾` swaps whole workshops.
- **Q7 ROW-FILL = TWO states on BUILD** — FILL (selected colour) → CLEAR (no mute state on
  the silent workbench).
- **Q8 THE BUTTONS ARE THE VERBS MADE PHYSICAL.** LEFT merged part button = COPY ROWS into
  that band (rows-with-picks, actives live). RIGHT per-row button = FLATTEN into that row
  (picked line → that rung/lane). Right buttons on ladder rows = flatten-into-ladder-row.
  Target decides; no arming.
- **Q9 SIDE BUTTONS WHILE PLAYING: INERT v1** (assignment is an edit-view act — stopped).
- **Q10 EMITTER M/S = PERFORM SCOPE ONLY** (the stage's mixer; machine/staging auditions
  unaffected).
- **Q11 ROW 8 (FREE) needs no selector.** Stopped → the shared workbench verbs reach it
  (PLACE/MOVE/DELETE cross grids in edit view). Playing → tap-to-voice per the FREE law.
  Stocking the menagerie = PLACE onto row 8, stopped.

## E. ITERATION 5 (Paul, promoted to `-build-page-iteration-5.md`)
- **§1 START/STOP = VIEW STATE.** STOPPED = EDIT view · PLAYING = PERFORMANCE view, per
  grid (its top handle drives it); applies to BOTH play and staging. The row buttons CHANGE
  APPEARANCE between states and the grid's touch semantics follow (edit verbs stopped;
  performance controls playing). FIRST-RUN: the play grid ships STOPPED; the user's first
  deployed part auto-starts it. Always-plays amends: the stage plays unless the USER stops it.
- **§2 ONE MUTATE.** Remove the footer MUTATE; the staging strip's MUTATE is THE mutate.
  (⚠ see Q4 conflict — the device kept the footer MUTATE.)
- **§3 DELETE IS SHARED across all three grids.** Arm DELETE → tap a staging/play cell =
  clear it; tap a CAST swatch = delete the colour AND its placed cells (litter semantics:
  no dialog, one undoable step, a brief "−1 colour · N cells" flash). Litter stays retired.

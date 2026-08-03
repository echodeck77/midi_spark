# MidiSpark Manual — SKELETON (top-down)
_Authored by Code (2026-08-04) from the live UI inventory. This is the STRUCTURE + the stable **doc-anchor IDs** +
a factual one-line "what it is" per control. The **Why / concept** lines are stubs — **the design side authors
them** (clarity, context, the laws behind each control). Every `{#anchor}` here is the contract for the DOCS TEST
(each registered control ID must have a matching anchor)._

Legend: **[A]** always-present · **[P]** PERFORM-only · **[E]** EDIT-only · **[dev]** debug-build only.
Anchor convention: flat kebab-case; `recv-`/`emit-` prefixes disambiguate the twin strip controls.
Every control entry is: `**Label** {#anchor} — factual what-it-is. _Why: TBD._`

---

## Chapter map (mirrors the surfaces)
1. PERFORM — the signal-flow desk
2. EDIT — the cell edit station
3. THE COG — the rig config
4. CONCEPTS — the plain-language laws (design authors from scratch)
5. BROWSERS — presets & cell library

---

# 1. PERFORM

## 1.1 The header / arrangement bar {#header} [A, both faces]
- **8×8 logotype** {#logo} — the app mark; long-press reveals the dev session loader. _Why: TBD._
- **PRESETS button** {#presets-open} — opens the preset browser; shows the loaded preset's name. _Why: TBD._
- **PERFORM / EDIT toggle** {#perform-edit-toggle} — switches the whole desk between the play face and the cell-edit face. _Why: TBD._
- **PASS · tempo readout** {#transport-readout} — display-only "P#·bpm" while playing. _Why: TBD._
- **UNDO** {#undo} — step the document back one edit. _Why: TBD._
- **REDO** {#redo} — step forward. _Why: TBD._
- **⚙ cog** {#cog-open} — opens the settings page (doubles as the scene-drag trash can). _Why: TBD._

## 1.2 Scenes {#scenes} [A, hidden by default — see {#display-scenes}]
- **Scene chips (16)** {#scene-chip} — save / arm-switch / re-cue / move / swap / trash the 16 scene slots. _Why: TBD._
  (sub-anchors: {#scene-save}, {#scene-arm}, {#scene-recue}, {#scene-move-swap}, {#scene-trash})

## 1.3 MIDI-input strips — the receivers {#receivers} [A], four doors R1–R4
- **Door header / ENABLE** {#recv-enable} — tap toggles the door's *listening* (channel + range summary shown; disabled = ignores incoming, an armed latch still feeds). _Why: TBD._
- **Live-input dot** {#recv-live-dot} — lights while an accepted live note is held (indicator). _Why: TBD._
- **BYPASS** {#bypass} — the door skips the grid and injects its held notes straight to its destination emitters. _Why: TBD._
- **LATCH arm** {#latch} — freeze the held chord so it keeps sounding after the keys lift. _Why: TBD._
- **KEYS \| CHORD** {#keys-chord} — the latch update rule: KEYS = per-note toggle (default); CHORD = detect-and-replace. _Why: TBD._
- **OCT− / OCT+ (input)** {#recv-oct} — ephemeral ±octave nudge on the door's incoming notes. _Why: TBD._
- **LIVE / MUTED (input)** {#recv-live} — the door's output gate into the grid (mute = feeds nothing, bypass included). _Why: TBD._
- **SOLO (input)** {#recv-solo} — additive input-solo set (excluded doors, incl. their bypass, go quiet). _Why: TBD._
- **Velocity fader (input)** {#recv-velocity} — idle meter (latch velocities when armed); drag = a FIXED absolute input-velocity override. _Why: TBD._

## 1.4 The 8×8 grid {#grid} [A]
- **Column keys (8)** {#column-key} — tap/hold to LOOP a column-subset (the lap); the active column lights. _Why: TBD._
- **Cell (tap)** {#cell-tap} — PERFORM: fires the cell's ON-TAP action (mute/alt/solo per config); routes/arms under a held verb or LADDER. _Why: TBD._
- **Cell (long-press / HOLD)** {#cell-hold} — audition the cell while held (HOLD-latch keeps it sounding). _Why: TBD._
- **Row-select rails (L/R)** {#row-rail} — tap a row to apply the active verb (or, in LADDER, enable the whole row). _Why: TBD._
- **The cell face (SEAL)** {#seal} — the derived glyph drawn on each cell (identity signature; twins share a figure). _Why: TBD._

## 1.5 Emitters — the outputs {#emitters} [A], four emitters A–D
- **Emitter header** {#emit-header} — enable dot · letter · stamp channel (amber when shared). Display-only. _Why: TBD._
- **Velocity fader (output)** {#emit-velocity} — drag forces output velocity (bottom = kill); momentary, springs back (HOLD-latches). _Why: TBD._
- **CLAIM** {#claim} — tap = own a pitch-class (suppress it on other emitters); drag = LEAK % bleed-through. _Why: TBD._
- **DUCK** {#duck} — tap = duck others under this emitter's activity; drag = amount %. _Why: TBD._
- **ALT** {#alt} — tap = join the turn-taking group; drag = notes-per-turn. _Why: TBD._
- **OCT− / OCT+ (output)** {#emit-oct} — ephemeral ±octave nudge on this emitter's output. _Why: TBD._
- **LIVE / MUTED (output)** {#emit-live} — the per-output enable/mute. _Why: TBD._
- **SOLO (output)** {#emit-solo} — additive emitter-solo set. _Why: TBD._

## 1.6 The master panel {#master} [A]
- **Master velocity fader** {#master-velocity} — momentary absolute over ALL output; bottom = kill every emitter. _Why: TBD._
- **MUTE / PANIC** {#master-mute} — tap = global emission kill; long-press = PANIC (hard all-notes-off). _Why: TBD._
- **KEY− / KEY+** {#master-key} — per-scene master transpose. _Why: TBD._

## 1.7 The verbs {#verbs} [P]
- **HOLD** {#hold} — sustain-latch for gestures (velocity overrides / audition / lap hold where you left them). _Why: TBD._
- **MUTE (arm)** {#mute-arm} — arm mute mode: a grid tap toggles a cell's mute. _Why: TBD._
- **SELECT** {#select} — reserved (shown "soon", inert). _Why: TBD (pending the retire/gather ruling)._
- **LADDER** {#ladder} — see 1.8.
- _(Dormant, coded but unsurfaced: PLACE / DELETE / COPY / PASTE + route-IN/OUT faces + stroke-paint — omit from v1 or mark "coming".)_

## 1.8 LADDER mode {#ladder-mode} [P]
- **LADDER toggle** {#ladder} — exclusive columns: at most one rung sounds per column. _Why: TBD._
- **Rung (cell) arm** {#ladder-rung} — tap a cell to become its column's rung; if the column is sounding it flashes (pending) then takes over at the next step. _Why: TBD._
- **Active-rung mute** {#ladder-mute} — tap the active rung to mute/unmute the column. _Why: TBD._
- **Row selector (LADDER)** {#ladder-row} — enable a whole row as the rung across columns (the sounding column arms). _Why: TBD._

## 1.9 Clock controls {#clock} [A]
- **STEP rate** {#step-rate} — the grid's step length (2/1 … 1/8). _Why: TBD._
- **SWING** {#swing} — 50…75 swing warp. _Why: TBD._

---

# 2. EDIT

## 2.1 The mode row {#edit-mode-row} [E]
- **ADD/EDIT \| MOVE \| MUTE \| CLEAR** {#edit-mode} — the edit action (only ADD/EDIT stages a selection set). _Why: TBD._
- **APPLY** {#edit-apply} — commit the staged edit as one undo step. _Why: TBD._
- **CANCEL** {#edit-cancel} — revert the staged edit. _Why: TBD._

## 2.2 The spike grid {#edit-grid} [E]
- **Cell select / clone** {#edit-cell-select} — tap builds the selection; empty tap births/clones a cell. _Why: TBD._
- **Anchor drop** {#edit-anchor} — long-press drops the anchor / fires the mode action. _Why: TBD._
- **Cell move** {#edit-cell-move} — drag to relocate/swap (MOVE mode). _Why: TBD._

## 2.3 Identity {#identity} [E]
- **SEAL preview** {#identity-seal} — the selected cell's derived glyph (display). _Why: TBD._
- **Colour picker (4×4)** {#colour} — re-tint the selection. _Why: TBD._

## 2.4 FROM · MIDI in {#edit-input} [E]
- **Receiver radio** {#cell-receiver} — which door (R1–R4 / none) this cell listens to. _Why: TBD._
- **SHIFT (transpose)** {#colour-transpose} — the Colour's semitone transpose. _Why: TBD._

## 2.5 The chain {#chain} [E]
- **LIBRARY button** {#library-open} — open the saved-cell browser. _Why: TBD._
- **Processor slot** {#chain-slot} — one stage of the chain; head + up to 8. _Why: TBD._
- **Type picker** {#processor-type} — choose the stage's machine (6 types). _Why: TBD._
- **Slot BYPASS** {#chain-bypass} — true-bypass this stage (passthrough). _Why: TBD._
- **Slot remove** {#chain-remove} — delete this stage. _Why: TBD._
- **+ ADD PROCESSOR** {#chain-add} — append a stage. _Why: TBD._
- Per-type params (each its own anchor):
  - **ARP** {#arp} — pattern · rate · oct · phase · gate. _Why: TBD._
  - **RATCHET** {#ratchet} — repeats · ramp. _Why: TBD._
  - **PASSGATE** {#passgate} — which of 1–4 passes open. _Why: TBD._
  - **STRUM** {#strum} — direction · spread · tilt. _Why: TBD._
  - **CHANCE** {#chance} — per-note probability. _Why: TBD._
  - **HARMONIZE** {#harmonize} — added voice intervals. _Why: TBD._

## 2.6 TO · MIDI out {#edit-output} [E]
- **MAIN destination** {#cell-dest} — which emitters (A–D) this cell feeds. _Why: TBD._
- **CHOP grid (8×3)** {#chop} — per-slice routing: MAIN / MUTE / ALT rows. _Why: TBD._
- **ALT destination** {#chop-alt-dest} — the emitters the chop ALT row routes to. _Why: TBD._

---

# 3. THE COG {#cog} [A]

## 3.1 MIDI input (per door) {#cog-input}
- **CH** {#recv-channel} — channel filter (OMNI default). _Why: TBD._
- **RANGE** {#range} — the door's admitted note window (lo–hi). _Why: TBD._
- **BYP→ destinations** {#bypass-dest} — which emitters the door's bypass injects to. _Why: TBD._
- **MPE** {#mpe} — MPE-merge for the door. _Why: TBD._

## 3.2 MIDI output (per emitter) {#cog-output}
- **CH (stamp)** {#emit-channel} — the emitter's output channel. _Why: TBD._

## 3.3 Display {#cog-display}
- **SCENES** {#display-scenes} — show/hide the scene row. _Why: TBD._

## 3.4 Health {#health} — VOICES / HELD / PANICS readout (indicator). _Why: TBD._

---

# 4. CONCEPTS {#concepts}
_Design authors these from scratch — the plain-language laws that make the controls make sense. Chapter one
(GUIDE-touching-things.md) already exists. Suggested sections to cover (Code's list of the laws the UI assumes):_
- The signal flow: **doors → the grid → emitters** (in, shape, out).
- **A door is a lens** (channel · range · MPE); ENABLE vs LIVE vs BYPASS (in-gate / out-gate / skip-grid).
- **The latch** (KEYS vs CHORD; hold the room).
- **The cell** = colour · seal · chain · destination; **twins**.
- **The chain** (head → stages; per-slot bypass; chop).
- **Emitter roles** — CLAIM / DUCK / ALT (ownership, dynamics, turns) + LEAK.
- **LADDER** (exclusive columns; arm-at-the-boundary).
- **Scenes & the lap** (arranged intensity; loop a column-subset).
- **Weather vs structure** (what clears on stop vs what persists).
- **The loud-mute law / one kill switch per door.**

---

# 5. BROWSERS
- **Preset browser** {#preset-browser} — save/load/delete user & factory presets. _Why: TBD._
- **Cell library** {#cell-library} — save/stamp/delete reusable cells & factory cells. _Why: TBD._

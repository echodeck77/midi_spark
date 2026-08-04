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

## 1.2 Scenes {#scenes} [A, hidden by default — see [SCENES](#display-scenes)]
- **Scene chips (16)** {#scene-chip} — save / arm-switch / re-cue / move / swap / trash the 16 scene slots. _Why: TBD._
  (sub-anchors: {#scene-save}, {#scene-arm}, {#scene-recue}, {#scene-move-swap}, {#scene-trash})

## 1.3 MIDI-input strips — the receivers {#receivers} [A], four doors R1–R4
- **Door header / ENABLE** {#recv-enable} — tap toggles the door's *listening* (channel + range summary shown; disabled = ignores incoming, an armed latch still feeds). _Why: The door's ear. Disable it and the door stops listening while everything it already holds keeps sounding — latch a pad on door A, close A, and play something new into B over the top. Close the door; keep the room._
- **Live-input dot** {#recv-live-dot} — lights while an accepted live note is held (indicator). _Why: TBD._
- **BYPASS** {#recv-bypass} — the door skips the grid and injects its held notes straight to its destination emitters. _Why: A straight wire from this door to your synths, skipping the grid — raw keys alongside the machines. Where it goes is set in the cog; whether it sounds still obeys LIVE, because LIVE silences a door completely or not at all._
- **LATCH arm** {#latch} — freeze the held chord so it keeps sounding after the keys lift. _Why: So the instrument keeps playing after your hands leave: hold a chord, latch it, and both hands are free for the grid. It's the difference between demonstrating the instrument and performing with it. Turning LATCH off is the only thing that lets the notes go._
- **KEYS \| CHORD** {#keys-chord} — the latch update rule: KEYS = per-note toggle (default); CHORD = detect-and-replace. _Why: Two ways of holding. KEYS is a garden: every key toggles itself in or out of the pool, so you build voicings one note at a time. CHORD is a camera: each new grab replaces the last. Switch freely — the pool survives the toggle._
- **OCT− / OCT+ (input)** {#recv-oct} — ephemeral ±octave nudge on the door's incoming notes. _Why: TBD._
- **LIVE / MUTED (input)** {#recv-live} — the door's output gate into the grid (mute = feeds nothing, bypass included). _Why: TBD._
- **SOLO (input)** {#recv-solo} — additive input-solo set (excluded doors, incl. their bypass, go quiet). _Why: TBD._
- **Velocity fader (input)** {#recv-velocity} — idle meter (latch velocities when armed); drag = a FIXED absolute input-velocity override. _Why: TBD._

## 1.4 The 8×8 grid {#grid} [A]
- **Column keys (8)** {#column-key} — tap/hold to LOOP a column-subset (the lap); the active column lights. _Why: TBD._
- **Cell (tap)** {#cell-tap} — PERFORM: fires the cell's ON-TAP action (mute/alt/solo per config); routes/arms under a held verb or LADDER. _Why: TBD._
- **Cell (long-press / HOLD)** {#cell-hold} — audition the cell while held (HOLD-latch keeps it sounding). _Why: TBD._
- **Row-select rails (L/R)** {#row-rail} — tap a row to apply the active verb (or, in LADDER, enable the whole row). _Why: TBD._
- **The cell face (SEAL)** {#seal} — the derived glyph drawn on each cell (identity signature; twins share a figure). _Why: The machine's signature, drawn from its actual settings — twins rhyme, strangers don't, and nothing you rename or recolour can dress it. When the cell sounds, a spark runs its wire; when the cell is silent, the circuit is still. Trust it over the colours: hue is what you chose, the seal is what's true._

## 1.5 Emitters — the outputs {#emitters} [A], four emitters A–D
- **Emitter header** {#emit-header} — enable dot · letter · stamp channel (amber when shared). Display-only. _Why: TBD._
- **Velocity fader (output)** {#emit-velocity} — drag forces output velocity (bottom = kill); momentary, springs back (HOLD-latches). _Why: TBD._
- **CLAIM** {#claim} — tap = own a pitch-class (suppress it on other emitters); drag = LEAK % bleed-through. _Why: TBD._
- **DUCK** {#emit-duck} — tap = duck others under this emitter's activity; drag = amount %. _Why: Sidechain pumping before any audio exists: while this output speaks, every OTHER output's new notes arrive quieter. Sounding notes never lurch — the law is admission-time only — so the pumping breathes instead of stuttering. At full depth it's a keyed gate: the band falls silent whenever this voice speaks._
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
- **LADDER** — see [§1.8](#ladder-mode).
- _(Dormant, coded but unsurfaced: PLACE / DELETE / COPY / PASTE + route-IN/OUT faces + stroke-paint — omit from v1 or mark "coming".)_

## 1.8 LADDER mode {#ladder-mode} [P]
- **LADDER toggle** {#ladder} — exclusive columns: at most one rung sounds per column. _Why: Turns each column into a stack of alternate takes with one live at a time, switched on the bar like clips. Its real gift is arranged intensity: scenes remember your rung choices, so "the drop" becomes a thing you painted, not a thing you scramble for._
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
- **Slot BYPASS** {#chain-bypass} — true-bypass this stage (passthrough). _Why: Every stage's true-bypass, and your debugger: eight processors deep, the question "which one is doing that?" is answered by switching suspects off one at a time. It's also a performance socket — a dormant stage left bypassed is a fill waiting for a trigger to punch it in._
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

# 4. CONCEPTS — HOW THIS INSTRUMENT THINKS {#concepts}
_Authored by the design side (MANUAL-concepts-and-voice, 2026-08-04). The plain-language laws that make the controls
make sense. GUIDE-touching-things.md slots in as the gestures chapter._

### The signal's journey {#concept-signal-flow}
You hold a chord. It enters through a DOOR (a MIDI input), lands in that door's pool of held notes, and every MACHINE
(cell) listening to that door transforms the pool into music — arpeggios, stutters, blooms. Each machine sends its
result down one or more WIRES (emitters) to your synths. Nothing is recorded anywhere along this path: the instrument
holds your *question*, and every pass of the playhead answers it again. Change the chord and every answer changes with it.

### Doors are lenses, not sockets {#concept-door-as-lens}
All four doors hear everything by default. They exist not to separate your gear but to SHAPE what comes in: one door
might latch chords, another hold a slowly-built pool, another drop everything an octave. Four views of the same hands.
(If you do run two keyboards, give a door a channel in the cog — separation is one tap away, never a requirement.)

### The latch {#concept-latch}
LATCH holds notes after your fingers leave. In KEYS, each key toggles itself into or out of the held pool — you garden
it, note by note. In CHORD, each new chord replaces the pool whole. Switching modes never clears what you've built;
only turning LATCH off lets go.

### Cells, twins, and seals {#concept-cells}
A cell is a little machine you assembled: where it listens, what its chain does, where it sends. Two cells with
identical machinery are TWINS — they edit together and wear the SAME SEAL, the circuit-like signature drawn from the
machine's own settings. Nobody chooses a seal and nobody can fake one: if two cells rhyme, they're the same machine;
if they don't, they aren't. The seal's spark moves only while the cell actually sounds.

### The chain {#concept-chain}
A cell's processors run top to bottom, up to eight deep. One of them — the last arp, ratchet, or strum — is the
DRIVER: it decides when notes happen. Everything above it shapes what the driver draws from; everything below decorates
each note it makes. Bypass any stage to hear the machine without it; that switch is also your debugger.

### The band {#concept-roles}
Your outputs aren't just plugs — they're band members with relationships. CLAIM says "these notes are mine; the rest
of you yield." DUCK says "everyone plays softer while I speak." ALT says "we take turns." None of them touch your
synths' sound; they negotiate WHO GETS WHICH NOTES, which is how four streams start sounding like players instead of copies.

### LADDER {#concept-ladder}
In LADDER mode each column holds alternate takes of an idea — one speaks, the rest wait. Tap a rung and it takes over
at the next bar, exactly like launching a clip. Scenes remember which rungs you chose, so intensity itself becomes
something you arrange.

### Scenes and the lap {#concept-scenes}
The playhead sweeps the columns; one full sweep is a LAP. Scenes snapshot the whole grid — machines, wiring, rung
choices, automation — and switch cleanly on the lap, so arrangement changes always land on the one.

### Weather and structure {#concept-weather}
Everything you do while performing — holds, mutes, rides, punches — is WEATHER: it springs back, leaves no residue,
and cannot damage the song. Everything you build in EDIT is STRUCTURE: it persists, scenes capture it, undo protects
it. The instrument never confuses the two, which is why you can play it recklessly.

### The kill-switch law {#concept-kill-switch}
Every door answers two separate questions. ENABLE: may notes come IN? (Disable a latched door and it keeps sounding —
the door closes, the room stays lit.) LIVE: may anything go OUT? LIVE off silences the door completely — derived music
and bypass alike, no exceptions. One switch for listening, one switch for speaking, and neither ever lies.

---

## THE WHY VOICE (style guide for filling every `_Why:_` stub)
_2–4 sentences. Sentence 1: what it's FOR (the musical intent, not the mechanism — the one-liner already has the
mechanism). Sentence 2: the law or promise it keeps, in plain words. Optional 3: the one trick worth knowing. Never
"simply", never "just", never a roadmap. Present tense, second person, calm._ Eight stubs are filled below as exemplars;
the design side fills the rest against this registry.

---

# 5. BROWSERS
- **Preset browser** {#preset-browser} — save/load/delete user & factory presets. _Why: TBD._
- **Cell library** {#cell-library} — save/stamp/delete reusable cells & factory cells. _Why: TBD._

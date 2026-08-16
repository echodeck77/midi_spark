# MidiSpark Manual — SKELETON (top-down)
_Authored by Code (2026-08-04) from the live UI inventory. This is the STRUCTURE + the stable **doc-anchor IDs** +
a factual one-line "what it is" per control. The **Why / concept** lines are stubs — **the design side authors
them** (clarity, context, the laws behind each control). Every `{#anchor}` here is the contract for the DOCS TEST
(each registered control ID must have a matching anchor)._

Legend: **[A]** always-present (the header bar tops every tab) · **[BUILD]** the BUILD workshop tab · **[GRID]** the GRID play desk · **[dev]** debug-build only.
Anchor convention: flat kebab-case; `recv-`/`emit-` prefixes disambiguate the twin strip controls.
Every control entry is: `**Label** {#anchor} — factual what-it-is. _Why: TBD._`

---

## Chapter map (mirrors the surfaces)
1. BUILD — the workshop (the default landing tab: assemble the machines, stage the part, deploy the piece)
2. PLAY — the signal-flow desk (the GRID tab + the shared header)
3. THE COG — the rig config
4. CONCEPTS — the plain-language laws (design authors from scratch)
5. BROWSERS — presets & cell library

---

# 1. BUILD — the workshop {#build} [BUILD, the default landing tab]
_The primary workshop, and the tab the plugin opens on. You assemble a machine as a COLOUR, stage it into a PART as
rows, pick where each row speaks, then FLATTEN the line and deploy it into THE PIECE. Teaching line:_ **stack machines
as rows · pick where each speaks · flatten weaves the line.**

## 1.1 The left column — the machine {#build-machine} [BUILD]
- **PLAY THIS MIDI CHAIN** {#build-play-chain} — audition the selected colour's machine alone and raw, without the part's column rules; press again to stop. _Why: Hear the machine you're shaping on its own terms — every column speaking, none of the part's picking — so you're tuning the sound, not the arrangement. It sounds alongside the piece, so the song never has to stop for you to listen._
- **CURRENT PART** {#build-part} — the part you're authoring; it starts UNASSIGNED and becomes PART n once deployed. **ADD PART** opens a fresh one. _Why: A part is one section's worth of staging on its way into the piece. It stays unnamed until it lands, because until then it's a workbench, not yet a member of the band._
- **INPUT** {#build-input} — the receiver door this part listens through (R1–R4); when the door is a PIANO door, a keyboard appears to pick the held notes. _Why: The part owns the door — every colour you build in it hears the same input. Point it once and the whole part reads the same hands._
- **OUTPUT** {#build-output} — the selected colour's emitters (A–D); a new colour soft-inherits the part's last-used wire. _Why: Where this machine's notes leave for your synths. The wire belongs to the colour, so the same machine always arrives at the same place, in any part._
- **THE CAST** {#build-cast} — the colour palette for this part; tap a swatch to SELECT it, "+" to create a new colour. _Why: The cast is your working set of machines, each wearing a colour. Selecting one aims every edit — chain, output, the staging stamp — at it. You curate the cast yourself; nothing joins it you didn't invite._
- **The CHAIN footer** {#build-chain} — the selected colour's processor chain, in signal order, along the foot of the workshop. _Why: The chain IS the machine — the few stages that decide what this colour does to the notes. It rides at the foot because it's what every other choice is about. An empty chain is a born-audible passthrough, waiting for its first idea._

## 1.2 THE PART — the staging grid {#build-staging} [BUILD]
- **The 8×8 staging grid** {#build-grid} — the centre grid where you stage the part: rows are candidate machines, columns are structure. _Why: You compose vertically. Each row is a machine you're auditioning as a line; the columns are where in the bar it may speak. The part is the shape you leave here._
- **Row buttons + SELECT · PLACE · MUTATE** {#build-rowmode} — the left-edge ROW BUTTONS are the placement gesture; the row-mode radio changes what a row button does. SELECT = whole-row rung pick across columns · PLACE = stamp the selected colour across the row · MUTATE = mint a value-tweaked variant colour. _Why: Placement is rows-only — a machine goes down a whole row at a time. SELECT chooses which rungs sound, PLACE lays the colour, MUTATE breeds a nudged sibling (≤3 tweaked params, provably distinct down to velocity and gate, its own hue) that pulses in the cast as a create-me candidate. One radio, three honest verbs; painting single cells on staging is gone._
- **A cell tap = a rung PICK** {#build-pick} — tapping a cell toggles that column's presence — which rung sounds there — never placement. _Why: On staging a cell asks WHEN, not WHAT. The tap turns a column's voice on or off; the machine got onto the row by the row button. Rows place, taps pick — the two never blur._
- **FLATTEN** {#build-flatten} — weaves the final line from the picks; mixed-colour lines are born at deployment. _Why: Flatten is the commit — it reads your picks down the columns and writes the one line the piece will play. Stack machines as rows, pick where each speaks, flatten weaves the line._

## 1.3 THE PIECE — the play grid {#build-piece} [BUILD]
- **The play grid of deployed parts** {#build-play-grid} — the right grid holds the parts you've deployed, each with per-row EMITTERS + a MUTE and a PLAY / EDIT VIEW radio. _Why: This is the song assembling itself — every part you flatten lands here as a row you can mute, route, and watch. PLAY runs it; EDIT VIEW lets you re-touch a row without it sounding._
- **The output console** {#build-console} — A–D strips and meters with per-part badges. _Why: Where the piece leaves for your synths — four wires, their levels, and a badge naming which part speaks on each. The last honest picture before the sound is someone else's._

## 1.4 Inside the chain — the processor slots {#build-chain-slots} [BUILD]
_The CHAIN footer opens the selected colour's stages. Editing a stage edits the colour — one machine, everywhere it's placed._
- **Processor slot** {#chain-slot} — one stage of the chain, in signal order; up to 8 deep. _Why: One stage of the machine, top to bottom. The chain IS the colour's sound-design surface: what this machine does is the sum of these few decisions._
- **Type picker** {#processor-type} — choose the stage's machine (6 types). _Why: Choose the stage's species. Six machines cover the ground: pattern, stutter, gate, rake, dice, and bloom — depth comes from combining them, not from a longer menu._
- **Slot BYPASS** {#chain-bypass} — true-bypass this stage (passthrough). _Why: Every stage's true-bypass, and your debugger: eight processors deep, the question "which one is doing that?" is answered by switching suspects off one at a time. It's also a performance socket — a dormant stage left bypassed is a fill waiting for a trigger to punch it in._
- **Slot remove** {#chain-remove} — delete this stage. _Why: Take the stage out entirely. Bypass first if you're only wondering; remove when you're sure._
- **+ ADD PROCESSOR** {#chain-add} — append a stage. _Why: Grow the machine, up to eight stages. The invitation is the empty chain's whole face: a new colour is a passthrough waiting for its first idea._
- Per-type params (each its own anchor):
  - **ARP** {#arp} — pattern · rate · oct · phase · gate. _Why: The pattern engine: it walks the held pool in an order, at a rate, across octaves. It's the instrument's oldest sentence — you hold the WHAT, the arp decides the WHEN and the ORDER — and every other stage is a modifier of its walk._
  - **RATCHET** {#ratchet} — repeats · ramp. _Why: Repeats within the step: one note becomes a burst. Drama in small doses — a ratchet stage is usually the difference between a pattern and a performance._
  - **PASSGATE** {#passgate} — which of 1–4 passes open. _Why: The lap-scale gate: which of the four passes this machine speaks on. Silence on a schedule is arrangement — the cell that only plays every fourth lap is a hook, not a hole._
  - **STRUM** {#strum} — direction · spread · tilt. _Why: The pool fanned in time, like a hand across strings — direction, width, and tilt. Chords stop being blocks and start being gestures._
  - **CHANCE** {#chance} — per-note probability. _Why: The dice: each would-be note plays or rests by probability. The pattern never breaks — it breathes; and because the dice are derived, the same seed always rolls the same weather when replayed._
  - **HARMONIZE** {#harmonize} — added voice intervals. _Why: Added voices at fixed intervals — the machine's own backing singers. They derive from each note as it happens, so the harmony follows your chord without ever knowing your song._

---

# 2. PLAY — the signal-flow desk

## 2.1 The header / arrangement bar {#header} [A — tops every tab]
- **8×8 logotype** {#logo} — the app mark; long-press opens the developer SELF-TEST panel (runs the built-in BuildSelfTest MIDI checks). _Why: The maker's mark, and quietly a handle: it holds the app's identity in hosts that show many plugins at once. The long-press panel is a developer door — it runs the engine's own MIDI self-tests; nothing behind it is needed to play._
- **PRESETS button** {#presets-open} — opens the preset browser; shows the loaded preset's name. _Why: Whole songs travel as presets: the grid, the scenes, the wiring, everything. Open this to change worlds; the name beside it tells you which world you're in._
- **Tab row** {#tab-bar} — the row of page tabs under the header. The tabs are **BUILD · GRID · MIDI IN · MIDI OUT · MACROS · AUTOMATION** — each opens a full-page surface (the workshop · the play grid · the input doors · the output wires · the macro bank · the automation lanes). _Why: One permanent address per surface, so a control always lives in the same place — you switch pages, you don't hunt through modes._
- **PASS · tempo readout** {#transport-readout} — display-only "P#·bpm" while playing. _Why: The pass counter and tempo, so you know where the lap is without watching the playhead. Display only; the host owns time here, always._
- **UNDO** {#undo} — step the document back one edit. _Why: Every structural change is one step back, including big ones. Undo covers STRUCTURE, not weather — performance gestures never need undoing because they never leave a mark._
- **REDO** {#redo} — step forward. _Why: The other direction. Together with undo it makes building a safe place to guess._
- **⚙ cog** {#cog-open} — opens the settings page (doubles as the scene-drag trash can). _Why: The rig lives here: the few set-once facts about your hardware and layout. If you're reaching for the cog mid-song, something belongs on a strip instead — tell us._

## 2.2 Scenes {#scenes} [A, hidden by default — see [SCENES](#display-scenes)]
- **Scene chips (16)** {#scene-chip} — save / arm-switch / re-cue / move / swap / trash the 16 scene slots. _Why: Scenes are the song's chapters: each chip snapshots the whole grid and recalls it on the lap, so arrangement moves always land on the one. Save with a tap on an empty chip, arm a switch with a tap on a full one; drag to move or swap — never to overwrite, because scenes are precious and the instrument won't let a drag destroy one._
  (sub-anchors: {#scene-save}, {#scene-arm}, {#scene-recue}, {#scene-move-swap}, {#scene-trash})

## 2.3 MIDI-input strips — the receivers {#receivers} [GRID], four doors R1–R4
- **Door header / ENABLE** {#recv-enable} — tap toggles the door's *listening* (channel + range summary shown; disabled = ignores incoming, an armed latch still feeds). _Why: The door's ear. Disable it and the door stops listening while everything it already holds keeps sounding — latch a pad on door A, close A, and play something new into B over the top. Close the door; keep the room._
- **Live-input dot** {#recv-live-dot} — lights while an accepted live note is held (indicator). _Why: A truth light: it burns only while an accepted live note is actually held at this door. When something seems silent, this dot answers the first question — is anything coming in?_
- **BYPASS** {#recv-bypass} — the door skips the grid and injects its held notes straight to its destination emitters. _Why: A straight wire from this door to your synths, skipping the grid — raw keys alongside the machines. Where it goes is set in the cog; whether it sounds still obeys LIVE, because LIVE silences a door completely or not at all._
- **LATCH arm** {#latch} — freeze the held chord so it keeps sounding after the keys lift. _Why: So the instrument keeps playing after your hands leave: hold a chord, latch it, and both hands are free for the grid. It's the difference between demonstrating the instrument and performing with it. Turning LATCH off is the only thing that lets the notes go._
- **KEYS \| CHORD** {#keys-chord} — the latch update rule: KEYS = per-note toggle (default); CHORD = detect-and-replace. _Why: Two ways of holding. KEYS is a garden: every key toggles itself in or out of the pool, so you build voicings one note at a time. CHORD is a camera: each new grab replaces the last. Switch freely — the pool survives the toggle._
- **OCT− / OCT+ (input)** {#recv-oct} — ephemeral ±octave nudge on the door's incoming notes. _Why: A quick register shove for everything this door hears — the whole pool up or down an octave without touching the keys. It's ephemeral by class: a performance nudge, not a setting._
- **LIVE / MUTED (input)** {#recv-live} — the door's output gate into the grid (mute = feeds nothing, bypass included). _Why: The door's speaking switch. Off means this door feeds nothing — grid and bypass alike — because a door is either in the music or it isn't; there are no half-silences to debug._
- **SOLO (input)** {#recv-solo} — additive input-solo set (excluded doors, incl. their bypass, go quiet). _Why: Isolate a door (or a few — solos add) to hear exactly what one input is contributing. Excluded doors go fully quiet, bypass included, under the same no-half-silences law._
- **Velocity fader (input)** {#recv-velocity} — idle meter (latch velocities when armed); drag = a FIXED absolute input-velocity override. _Why: At rest it's a meter — the door's held velocities as marks. Dragged, it becomes an absolute override: every note this door sends carries YOUR level until you let the music's own dynamics back. The bottom is a kill — velocity zero is silence, honestly._

## 2.4 The 8×8 grid {#grid} [GRID]
- **Column keys (8)** {#column-key} — tap/hold to LOOP a column-subset (the lap); the active column lights. _Why: The lap doesn't have to be all eight columns: tap a key to loop one column, more keys to loop a subset. The same narrowing serves two uses — auditioning while you shape, looping while you play._
- **Cell (tap)** {#cell-tap} — fires the cell's ON-TAP action (mute/alt/solo per config); in SINGLE mode a tap arms that cell as its column's rung. _Why: On the play grid a cell is a pad: tapping fires whatever action its maker gave it, and under SINGLE it nominates the column's one live rung. What the action is, the cell's own face tells you; what it never is, is destructive._
- **Cell (long-press / HOLD)** {#cell-hold} — audition the cell while held (HOLD-latch keeps it sounding). _Why: Press and hold any cell to hear it alone while your finger stays — an audition without commitment. HOLD (the verb) can latch that audition so your hand is free again._
- **Row-select rails (L/R)** {#row-rail} — tap a row to act on it whole (mute the row, or in SINGLE mode enable the whole row as the rung). _Why: The whole-row handle: one tap applies the action across the row. Rows are how this instrument thinks in layers, and the rails are how you grab a layer whole._
- **The cell face (SEAL)** {#seal} — the derived glyph drawn on each cell (identity signature; twins share a figure). _Why: The machine's signature, drawn from its actual settings — twins rhyme, strangers don't, and nothing you rename or recolour can dress it. When the cell sounds, a spark runs its wire; when the cell is silent, the circuit is still. Trust it over the colours: hue is what you chose, the seal is what's true._

## 2.5 Emitters — the outputs {#emitters} [GRID], four emitters A–D
- **Cabling in the host** {#emit-cabling} — connect your synths to A–D **or** to ALL, never both. _Why: Every note goes out twice: on its own emitter cable (A–D) and on the ALL cable. In the host, patch a synth to ONE of them — pick the per-emitter cables (A–D) for independent routing, or the single ALL cable to hear everything on one port. Wiring a synth to an emitter AND to ALL double-triggers it._
- **Emitter header** {#emit-header} — enable dot · letter · stamp channel (amber when shared). Display-only. _Why: The output's nameplate: its letter, its channel, and whether it's lit. Amber on the channel means two emitters share it — legal, sometimes intended, worth knowing._
- **Velocity fader (output)** {#emit-velocity} — drag forces output velocity (bottom = kill); momentary, springs back (HOLD-latches). _Why: The output's hand on the dynamics: drag to force every note on this wire to one level, spring back to let the music breathe again. Bottom is a kill. HOLD latches it where you leave it — the whisper-drop, one finger._
- **CLAIM** {#claim} — tap = own a pitch-class (suppress it on other emitters); drag = LEAK % bleed-through. _Why: This output owns what it's sounding: matching notes bound for other emitters yield to it. LEAK (the drag) lets the yielded notes through as shadows instead of silence — ownership with mercy. It's how a lead stays THE lead without muting the band._
- **DUCK** {#emit-duck} — tap = duck others under this emitter's activity; drag = amount %. _Why: Sidechain pumping before any audio exists: while this output speaks, every OTHER output's new notes arrive quieter. Sounding notes never lurch — the law is admission-time only — so the pumping breathes instead of stuttering. At full depth it's a keyed gate: the band falls silent whenever this voice speaks._
- **ALT** {#alt} — tap = join the turn-taking group; drag = notes-per-turn. _Why: Turn-taking: lit emitters form a ring and share the notes around it, so one line hockets across your synths — or a chord deals itself one voice per box. The drag sets how many notes each turn takes._
- **OCT− / OCT+ (output)** {#emit-oct} — ephemeral ±octave nudge on this emitter's output. _Why: The output's register nudge — this wire up or down an octave, live, ephemeral. Pair two emitters an octave apart and ALT between them for instant width._
- **LIVE / MUTED (output)** {#emit-live} — the per-output enable/mute. _Why: The wire's speaking switch: off is fully off. Same law as the doors — no half-silences, ever._
- **SOLO (output)** {#emit-solo} — additive emitter-solo set. _Why: Hear one output (or a chosen few) alone. Solos add; everyone else waits._

## 2.6 The master panel {#master} [GRID]
- **Master velocity fader** {#master-velocity} — momentary absolute over ALL output; bottom = kill every emitter. _Why: One fader over the whole band: the drop, the swell, the whisper — every emitter at once, springing back when you let go. The bottom kills everything, which is sometimes exactly the gesture._
- **MUTE / PANIC** {#master-mute} — tap = global emission kill; long-press = PANIC (hard all-notes-off). _Why: The big quiet: tap silences all emission; long-press is PANIC — a hard all-notes-off for the one day something external misbehaves. You will rarely need it; it's here so you never fear needing it._
- **KEY− / KEY+** {#master-key} — per-scene master transpose. _Why: The song's transpose, per scene: the whole arrangement up or down in semitones, structurally. Your held chord plus KEY is how one hand plays in every key._

## 2.7 The CONTROLS panel {#verbs} [GRID]
- **CONTROLS panel** — the placeholder engine bank beside the macros under the grid: **RANDOMIZE · AUTOMATION · MUTATE · AUTOPLAY**. _Why: The four engines the play desk is growing into — a dice for the sound, an automation surface, a bounded mutator, and a self-player. They read as seats now; each lights up as its engine lands. Nothing here can damage the song._

## 2.8 SINGLE | MULTI — LADDER mode {#ladder-mode} [GRID]
- **SINGLE | MULTI toggle** {#ladder} — the title-bar mode: SINGLE makes the columns exclusive (at most one rung sounds per column), MULTI lets every populated rung sound. _Why: SINGLE turns each column into a stack of alternate takes with one live at a time, switched on the bar like clips. Its real gift is arranged intensity: scenes remember your rung choices, so "the drop" becomes a thing you painted, not a thing you scramble for. (Hidden on BUILD — staging owns its own picking.)_
- **Rung (cell) arm** {#ladder-rung} — tap a cell to become its column's rung; if the column is sounding it flashes (pending) then takes over at the next step. _Why: In LADDER, tapping a cell nominates it as its column's voice. If the column is mid-sound the rung flashes — pending — and takes over at the next step, so switches always land in time. You can't be early; the instrument won't let you._
- **Active-rung mute** {#ladder-mute} — tap the active rung to mute/unmute the column. _Why: Tap the ACTIVE rung and the column holds its breath: muted, place kept, one tap from returning. The gap is a musical object too._
- **Row selector (LADDER)** {#ladder-row} — enable a whole row as the rung across columns (the sounding column arms). _Why: The whole-ladder handle: one tap on the rail makes an entire row the rung everywhere — the full band drops to STILL, or lifts to STORM, in one gesture. The sounding column arms rather than cuts, per the ladder's own law._

## 2.9 Clock controls {#clock} [A]
- **STEP rate** {#step-rate} — the grid's step length (2/1 … 1/8). _Why: How much time one column is: the grid's stride, from two bars down to an eighth. Everything derives from it, so changing it re-times the whole world coherently — nothing drifts, because nothing is recorded._
- **SWING** {#swing} — 50…75 swing warp. _Why: The lean: even steps stay put, odd steps arrive late, from straight (50) to hard shuffle (75). It warps the clock the machines read, so every cell swings together — the whole instrument has one hip._

---

# 3. THE COG {#cog} [A]

## 3.1 MIDI input (per door) {#cog-input}
- **CH** {#recv-channel} — channel filter (OMNI default). _Why: OMNI unless you're separating controllers: give a door a channel and it becomes one keyboard's private entrance. One tap, and the two-player rig exists; untouched, and no one ever meets this setting._
- **RANGE** {#range} — the door's admitted note window (lo–hi). _Why: The door's window: only notes between the posts get in. Split one keyboard across two doors — bass below, keys above — and each half feeds different machines, no external tools._
- **BYP→ destinations** {#bypass-dest} — which emitters the door's bypass injects to. _Why: Where this door's BYPASS injects: choose the wires raw playing should reach. The straight line through the instrument, aimed once, here._
- **MPE** {#mpe} — MPE-merge for the door. _Why: For expressive controllers that spread one performance across many channels: MPE folds the spread back into one voice stream for the door. On = the controller behaves like itself; off = channels stay channels._

## 3.2 MIDI output (per emitter) {#cog-output}
- **CH (stamp)** {#emit-channel} — the emitter's output channel. _Why: The wire's address at the synth: which channel this emitter stamps on everything it sends. Two emitters may share — the header shows amber when they do._

## 3.3 Display {#cog-display}
- **SCENES** {#display-scenes} — show/hide the scene row. _Why: The scene row costs a row of screen; hide it when a song doesn't need chapters. The scenes themselves persist either way — this hides furniture, never work._

## 3.4 Health {#health} — VOICES / HELD / PANICS readout (indicator). _Why: The engine's pulse: voices sounding, notes held, and whether PANIC has ever fired. When everything is fine it's a number you never read; when something's odd it's the first witness._

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
and cannot damage the song. Everything you build in BUILD is STRUCTURE: it persists, scenes capture it, undo protects
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
- **Preset browser** {#preset-browser} — save/load/delete user & factory presets. _Why: Songs live here whole — yours and the factory's. Factory presets are also lessons: each one demonstrates one idea with its rig declared, so browsing is a course you can play._
- **Cell library** {#cell-library} — save/stamp/delete reusable cells & factory cells. _Why: Machines live here portable — chain and settings, minus the wiring (a machine learns its address when you place it). Save what you'd miss; stamp it into any song; this is your sound as a collection._

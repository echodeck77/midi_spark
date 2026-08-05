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
- **8×8 logotype** {#logo} — the app mark; long-press reveals the dev session loader. _Why: The maker's mark, and quietly a handle: it holds the app's identity in hosts that show many plugins at once. The long-press loader is a developer door; nothing behind it is needed to play._
- **PRESETS button** {#presets-open} — opens the preset browser; shows the loaded preset's name. _Why: Whole songs travel as presets: the grid, the scenes, the wiring, everything. Open this to change worlds; the name beside it tells you which world you're in._
- **PERFORM / EDIT toggle** {#perform-edit-toggle} — switches the whole desk between the play face and the cell-edit face. _Why: The instrument has two faces: PLAY the music or BUILD the machines. The toggle keeps them honest — you always know which face your fingers are on, and nothing in PERFORM can break what you built in EDIT._
- **PASS · tempo readout** {#transport-readout} — display-only "P#·bpm" while playing. _Why: The pass counter and tempo, so you know where the lap is without watching the playhead. Display only; the host owns time here, always._
- **UNDO** {#undo} — step the document back one edit. _Why: Every structural change is one step back, including big ones. Undo covers STRUCTURE, not weather — performance gestures never need undoing because they never leave a mark._
- **REDO** {#redo} — step forward. _Why: The other direction. Together with undo it makes EDIT a safe place to guess._
- **⚙ cog** {#cog-open} — opens the settings page (doubles as the scene-drag trash can). _Why: The rig lives here: the few set-once facts about your hardware and layout. If you're reaching for the cog mid-song, something belongs on a strip instead — tell us._

## 1.2 Scenes {#scenes} [A, hidden by default — see [SCENES](#display-scenes)]
- **Scene chips (16)** {#scene-chip} — save / arm-switch / re-cue / move / swap / trash the 16 scene slots. _Why: Scenes are the song's chapters: each chip snapshots the whole grid and recalls it on the lap, so arrangement moves always land on the one. Save with a tap on an empty chip, arm a switch with a tap on a full one; drag to move or swap — never to overwrite, because scenes are precious and the instrument won't let a drag destroy one._
  (sub-anchors: {#scene-save}, {#scene-arm}, {#scene-recue}, {#scene-move-swap}, {#scene-trash})

## 1.3 MIDI-input strips — the receivers {#receivers} [A], four doors R1–R4
- **Door header / ENABLE** {#recv-enable} — tap toggles the door's *listening* (channel + range summary shown; disabled = ignores incoming, an armed latch still feeds). _Why: The door's ear. Disable it and the door stops listening while everything it already holds keeps sounding — latch a pad on door A, close A, and play something new into B over the top. Close the door; keep the room._
- **Live-input dot** {#recv-live-dot} — lights while an accepted live note is held (indicator). _Why: A truth light: it burns only while an accepted live note is actually held at this door. When something seems silent, this dot answers the first question — is anything coming in?_
- **BYPASS** {#recv-bypass} — the door skips the grid and injects its held notes straight to its destination emitters. _Why: A straight wire from this door to your synths, skipping the grid — raw keys alongside the machines. Where it goes is set in the cog; whether it sounds still obeys LIVE, because LIVE silences a door completely or not at all._
- **LATCH arm** {#latch} — freeze the held chord so it keeps sounding after the keys lift. _Why: So the instrument keeps playing after your hands leave: hold a chord, latch it, and both hands are free for the grid. It's the difference between demonstrating the instrument and performing with it. Turning LATCH off is the only thing that lets the notes go._
- **KEYS \| CHORD** {#keys-chord} — the latch update rule: KEYS = per-note toggle (default); CHORD = detect-and-replace. _Why: Two ways of holding. KEYS is a garden: every key toggles itself in or out of the pool, so you build voicings one note at a time. CHORD is a camera: each new grab replaces the last. Switch freely — the pool survives the toggle._
- **OCT− / OCT+ (input)** {#recv-oct} — ephemeral ±octave nudge on the door's incoming notes. _Why: A quick register shove for everything this door hears — the whole pool up or down an octave without touching the keys. It's ephemeral by class: a performance nudge, not a setting._
- **LIVE / MUTED (input)** {#recv-live} — the door's output gate into the grid (mute = feeds nothing, bypass included). _Why: The door's speaking switch. Off means this door feeds nothing — grid and bypass alike — because a door is either in the music or it isn't; there are no half-silences to debug._
- **SOLO (input)** {#recv-solo} — additive input-solo set (excluded doors, incl. their bypass, go quiet). _Why: Isolate a door (or a few — solos add) to hear exactly what one input is contributing. Excluded doors go fully quiet, bypass included, under the same no-half-silences law._
- **Velocity fader (input)** {#recv-velocity} — idle meter (latch velocities when armed); drag = a FIXED absolute input-velocity override. _Why: At rest it's a meter — the door's held velocities as marks. Dragged, it becomes an absolute override: every note this door sends carries YOUR level until you let the music's own dynamics back. The bottom is a kill — velocity zero is silence, honestly._

## 1.4 The 8×8 grid {#grid} [A]
- **Column keys (8)** {#column-key} — tap/hold to LOOP a column-subset (the lap); the active column lights. _Why: The lap doesn't have to be all eight columns: tap a key to loop one column, more keys to loop a subset. It's the audition tool in EDIT and a performance loop in PERFORM — the same narrowing, two uses._
- **Cell (tap)** {#cell-tap} — PERFORM: fires the cell's ON-TAP action (mute/alt/solo per config); routes/arms under a held verb or LADDER. _Why: In PERFORM a cell is a pad: tapping fires whatever action its maker gave it. What that is, the cell's own face and the manual's TRIGGERS entries tell you; what it never is, is destructive._
- **Cell (long-press / HOLD)** {#cell-hold} — audition the cell while held (HOLD-latch keeps it sounding). _Why: Press and hold any cell to hear it alone while your finger stays — an audition without commitment. HOLD (the verb) can latch that audition so your hand is free again._
- **Row-select rails (L/R)** {#row-rail} — tap a row to apply the active verb (or, in LADDER, enable the whole row). _Why: The whole-row handle: one tap applies the armed action across the row. Rows are how this instrument thinks in layers, and the rails are how you grab a layer whole._
- **The cell face (SEAL)** {#seal} — the derived glyph drawn on each cell (identity signature; twins share a figure). _Why: The machine's signature, drawn from its actual settings — twins rhyme, strangers don't, and nothing you rename or recolour can dress it. When the cell sounds, a spark runs its wire; when the cell is silent, the circuit is still. Trust it over the colours: hue is what you chose, the seal is what's true._

## 1.5 Emitters — the outputs {#emitters} [A], four emitters A–D
- **Emitter header** {#emit-header} — enable dot · letter · stamp channel (amber when shared). Display-only. _Why: The output's nameplate: its letter, its channel, and whether it's lit. Amber on the channel means two emitters share it — legal, sometimes intended, worth knowing._
- **Velocity fader (output)** {#emit-velocity} — drag forces output velocity (bottom = kill); momentary, springs back (HOLD-latches). _Why: The output's hand on the dynamics: drag to force every note on this wire to one level, spring back to let the music breathe again. Bottom is a kill. HOLD latches it where you leave it — the whisper-drop, one finger._
- **CLAIM** {#claim} — tap = own a pitch-class (suppress it on other emitters); drag = LEAK % bleed-through. _Why: This output owns what it's sounding: matching notes bound for other emitters yield to it. LEAK (the drag) lets the yielded notes through as shadows instead of silence — ownership with mercy. It's how a lead stays THE lead without muting the band._
- **DUCK** {#emit-duck} — tap = duck others under this emitter's activity; drag = amount %. _Why: Sidechain pumping before any audio exists: while this output speaks, every OTHER output's new notes arrive quieter. Sounding notes never lurch — the law is admission-time only — so the pumping breathes instead of stuttering. At full depth it's a keyed gate: the band falls silent whenever this voice speaks._
- **ALT** {#alt} — tap = join the turn-taking group; drag = notes-per-turn. _Why: Turn-taking: lit emitters form a ring and share the notes around it, so one line hockets across your synths — or a chord deals itself one voice per box. The drag sets how many notes each turn takes._
- **OCT− / OCT+ (output)** {#emit-oct} — ephemeral ±octave nudge on this emitter's output. _Why: The output's register nudge — this wire up or down an octave, live, ephemeral. Pair two emitters an octave apart and ALT between them for instant width._
- **LIVE / MUTED (output)** {#emit-live} — the per-output enable/mute. _Why: The wire's speaking switch: off is fully off. Same law as the doors — no half-silences, ever._
- **SOLO (output)** {#emit-solo} — additive emitter-solo set. _Why: Hear one output (or a chosen few) alone. Solos add; everyone else waits._

## 1.6 The master panel {#master} [A]
- **Master velocity fader** {#master-velocity} — momentary absolute over ALL output; bottom = kill every emitter. _Why: One fader over the whole band: the drop, the swell, the whisper — every emitter at once, springing back when you let go. The bottom kills everything, which is sometimes exactly the gesture._
- **MUTE / PANIC** {#master-mute} — tap = global emission kill; long-press = PANIC (hard all-notes-off). _Why: The big quiet: tap silences all emission; long-press is PANIC — a hard all-notes-off for the one day something external misbehaves. You will rarely need it; it's here so you never fear needing it._
- **KEY− / KEY+** {#master-key} — per-scene master transpose. _Why: The song's transpose, per scene: the whole arrangement up or down in semitones, structurally. Your held chord plus KEY is how one hand plays in every key._

## 1.7 The verbs {#verbs} [P]
- **HOLD** {#hold} — sustain-latch for gestures (velocity overrides / audition / lap hold where you left them). _Why: The sustain pedal for gestures: whatever you're holding — a velocity ride, an audition, a lap — HOLD keeps where you left it so your hand can leave. Release HOLD and everything springs home. It's the law of weather, given a latch._
- **MUTE (arm)** {#mute-arm} — arm mute mode: a grid tap toggles a cell's mute. _Why: Arm it and the grid becomes a mute board: tap cells to silence or wake them, tap MUTE again to put the board away. Muting is chrome — the machine underneath keeps deriving, so unmuting is always seamless._
- **SELECT** {#select} — reserved (shown "soon", inert). _Why: TBD (pending the retire/gather ruling)._
- **LADDER** — see [§1.8](#ladder-mode).
- _(Dormant, coded but unsurfaced: PLACE / DELETE / COPY / PASTE + route-IN/OUT faces + stroke-paint — omit from v1 or mark "coming".)_

## 1.8 LADDER mode {#ladder-mode} [P]
- **LADDER toggle** {#ladder} — exclusive columns: at most one rung sounds per column. _Why: Turns each column into a stack of alternate takes with one live at a time, switched on the bar like clips. Its real gift is arranged intensity: scenes remember your rung choices, so "the drop" becomes a thing you painted, not a thing you scramble for._
- **Rung (cell) arm** {#ladder-rung} — tap a cell to become its column's rung; if the column is sounding it flashes (pending) then takes over at the next step. _Why: In LADDER, tapping a cell nominates it as its column's voice. If the column is mid-sound the rung flashes — pending — and takes over at the next step, so switches always land in time. You can't be early; the instrument won't let you._
- **Active-rung mute** {#ladder-mute} — tap the active rung to mute/unmute the column. _Why: Tap the ACTIVE rung and the column holds its breath: muted, place kept, one tap from returning. The gap is a musical object too._
- **Row selector (LADDER)** {#ladder-row} — enable a whole row as the rung across columns (the sounding column arms). _Why: The whole-ladder handle: one tap on the rail makes an entire row the rung everywhere — the full band drops to STILL, or lifts to STORM, in one gesture. The sounding column arms rather than cuts, per the ladder's own law._

## 1.9 Clock controls {#clock} [A]
- **STEP rate** {#step-rate} — the grid's step length (2/1 … 1/8). _Why: How much time one column is: the grid's stride, from two bars down to an eighth. Everything derives from it, so changing it re-times the whole world coherently — nothing drifts, because nothing is recorded._
- **SWING** {#swing} — 50…75 swing warp. _Why: The lean: even steps stay put, odd steps arrive late, from straight (50) to hard shuffle (75). It warps the clock the machines read, so every cell swings together — the whole instrument has one hip._

---

# 2. EDIT

## 2.1 The mode row {#edit-mode-row} [E]
- **ADD/EDIT \| MOVE \| MUTE \| CLEAR** {#edit-mode} — the edit action (only ADD/EDIT stages a selection set). _Why: Four intents, one at a time: ADD/EDIT builds and shapes, MOVE relocates, MUTE paints silence, CLEAR removes. The row means your taps always do what the lit button says — no modes hiding inside modes._
- **APPLY** {#edit-apply} — commit the staged edit as one undo step. _Why: The staged edit becomes real, as ONE undo step no matter how many cells it touched. Big changes, small history._
- **CANCEL** {#edit-cancel} — revert the staged edit. _Why: Everything since you started staging unwinds — births included. EDIT is a place to try things precisely because leaving without applying costs nothing._

## 2.2 The spike grid {#edit-grid} [E]
- **Cell select / clone** {#edit-cell-select} — tap builds the selection; empty tap births/clones a cell. _Why: Tap cells into the working set; tap an empty space and a cell is BORN there, already playing (a newborn passes its door straight through — sound first, shaping after). Every cell you add clones the anchor, so the set stays a set of twins._
- **Anchor drop** {#edit-anchor} — long-press drops the anchor / fires the mode action. _Why: The first cell you chose is the anchor — the template the others clone, protected from a stray tap by needing a long-press to release. It's the "which one am I copying?" question, answered structurally._
- **Cell move** {#edit-cell-move} — drag to relocate/swap (MOVE mode). _Why: Drag a cell to a new slot; drop on an occupied one and they trade places. Rearranging is swapping, never destroying — the grid's furniture rule._

## 2.3 Identity {#identity} [E]
- **SEAL preview** {#identity-seal} — the selected cell's derived glyph (display). _Why: The selected machine's signature, large: watch it re-route as you change the chain, because the seal IS the settings. When two cells' seals match here, they are the same machine everywhere._
- **Colour picker (4×4)** {#colour} — re-tint the selection. _Why: Hue is yours: it groups, it labels, it means whatever you decide. It's the one mark on a cell the instrument never derives — your handwriting next to the machine's._

## 2.4 FROM · MIDI in {#edit-input} [E]
- **Receiver radio** {#cell-receiver} — which door (R1–R4 / none) this cell listens to. _Why: Which door this machine listens to. One choice, radio-simple, and the whole signal path upstream of the chain is decided._
- **SHIFT (transpose)** {#colour-transpose} — the Colour's semitone transpose. _Why: The machine's own key offset, in semitones — this cell's voice sits a third up or an octave down from the pool it reads. Layer transposed twins for instant harmony that still follows your hands._

## 2.5 The chain {#chain} [E]
- **LIBRARY button** {#library-open} — open the saved-cell browser. _Why: Machines you'll want again live here: save a chain, stamp it anywhere, in any song. The library is how an afternoon's sound design becomes your permanent vocabulary._
- **Processor slot** {#chain-slot} — one stage of the chain; head + up to 8. _Why: One stage of the machine, in signal order, top to bottom. The chain IS the instrument's sound-design surface: what this cell does is the sum of these few decisions._
- **Type picker** {#processor-type} — choose the stage's machine (6 types). _Why: Choose the stage's species. Six machines cover the ground: pattern, stutter, gate, rake, dice, and bloom — depth comes from combining them, not from a longer menu._
- **Slot BYPASS** {#chain-bypass} — true-bypass this stage (passthrough). _Why: Every stage's true-bypass, and your debugger: eight processors deep, the question "which one is doing that?" is answered by switching suspects off one at a time. It's also a performance socket — a dormant stage left bypassed is a fill waiting for a trigger to punch it in._
- **Slot remove** {#chain-remove} — delete this stage. _Why: Take the stage out entirely. Bypass first if you're only wondering; remove when you're sure._
- **+ ADD PROCESSOR** {#chain-add} — append a stage. _Why: Grow the machine, up to eight stages. The invitation is the empty chain's whole face: a newborn cell is a passthrough waiting for its first idea._
- Per-type params (each its own anchor):
  - **ARP** {#arp} — pattern · rate · oct · phase · gate. _Why: The pattern engine: it walks the held pool in an order, at a rate, across octaves. It's the instrument's oldest sentence — you hold the WHAT, the arp decides the WHEN and the ORDER — and every other stage is a modifier of its walk._
  - **RATCHET** {#ratchet} — repeats · ramp. _Why: Repeats within the step: one note becomes a burst. Drama in small doses — a ratchet stage is usually the difference between a pattern and a performance._
  - **PASSGATE** {#passgate} — which of 1–4 passes open. _Why: The lap-scale gate: which of the four passes this machine speaks on. Silence on a schedule is arrangement — the cell that only plays every fourth lap is a hook, not a hole._
  - **STRUM** {#strum} — direction · spread · tilt. _Why: The pool fanned in time, like a hand across strings — direction, width, and tilt. Chords stop being blocks and start being gestures._
  - **CHANCE** {#chance} — per-note probability. _Why: The dice: each would-be note plays or rests by probability. The pattern never breaks — it breathes; and because the dice are derived, the same seed always rolls the same weather when replayed._
  - **HARMONIZE** {#harmonize} — added voice intervals. _Why: Added voices at fixed intervals — the machine's own backing singers. They derive from each note as it happens, so the harmony follows your chord without ever knowing your song._

## 2.6 TO · MIDI out {#edit-output} [E]
- **MAIN destination** {#cell-dest} — which emitters (A–D) this cell feeds. _Why: Which wires this machine feeds. More than one is normal — fan a cell to two synths and let the RACK's relationships sort out who says what._
- **CHOP grid (8×3)** {#chop} — per-slice routing: MAIN / MUTE / ALT rows. _Why: The cell's bar, cut into eight slices, each routed: MAIN, silent, or thrown to the ALT wires. Rhythm and routing in one drawing — the trance-gate and the auto-pan are both just patterns here._
- **ALT destination** {#chop-alt-dest} — the emitters the chop ALT row routes to. _Why: Where the thrown slices land. Set it once and the chop row's ALT marks all mean the same elsewhere — one alternative address per machine, kept simple on purpose._

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
- **Preset browser** {#preset-browser} — save/load/delete user & factory presets. _Why: Songs live here whole — yours and the factory's. Factory presets are also lessons: each one demonstrates one idea with its rig declared, so browsing is a course you can play._
- **Cell library** {#cell-library} — save/stamp/delete reusable cells & factory cells. _Why: Machines live here portable — chain and settings, minus the wiring (a machine learns its address when you place it). Save what you'd miss; stamp it into any song; this is your sound as a collection._

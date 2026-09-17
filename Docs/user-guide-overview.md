# 8×8 State — User Guide (section overview)

_A simple, plain-language tour of each part of the app. This is an overview, not a full manual, and it
describes what's actually on screen today (some deeper features exist in the engine but aren't surfaced yet)._

## The idea
**Don't sequence notes — sequence what happens to them.** You hold chords in; a grid of *processors* treats
those notes over time (arpeggiate, ratchet, re-voice, gate, and so on); the result plays out. The plugin puts
out MIDI on five cables: a combined **ALL** stream plus four separate cables **A–D**.

## The workbench (SELECT / PART)
There's **one main grid**, and it's in one of two states depending on which ferry you open:

- **SELECT** — the browser. The grid becomes an 8×8 of tiles, each a complete *machine* (a chain of
  processors) shown as a little piano-roll fingerprint. Tap a tile to hear it against whatever you're playing;
  drag the one you like onto a play ferry to keep it.
- **PART** — the editor. Opening a populated ferry shows its *part* as a step grid (8, or up to 16, columns).
  Each column has one active row ("rung"); the playhead sweeps through them. The machine's chain editor (the
  card) sits below the grid.

You move between the two by tapping ferries in the row above the grid — an empty ferry opens the SELECT
browser, a populated one opens its part.

## Play ferries
The row of **8 slots** above the grid. Each ferry holds a full part.
- **Selector** (top) — opens that ferry's part on the bench (empty → the SELECT browser).
- **Play/Stop** (the big button) — starts/stops that ferry. Several can play at once; the one on the bench
  plays through the workbench grid, the others play in the background.
- **M (mute)** — silences that ferry's audio; its play light stays on so you can see it's still running.
- **S (solo)** — when any ferry is soloed, only soloed ferries are heard.
  A muted or solo-excluded ferry — and, if it's the one on the bench, its part grid — dims to show it's silenced.

## The machine (the chain)
A cell is a **machine** — a chain of up to **8 processors** in series, in signal order. Edit the chain in the
card below the grid: add/remove stages, choose each stage's type, and bypass any stage to hear its effect.
Editing a machine changes it everywhere that machine is placed.

## Processors
There are ~32 processor types, grouped by what they do:
- **MELODY** (arp, riff…), **HARMONY** (harmonize, chords, avoid/lock-to-key…),
  **RHYTHM** (ratchet, euclid, burst, weave…), **DYNAMICS** (chance, velocity, humanize…),
  **CONTROL** (mod — shaped CC/LFO, glide…), **TIME** (echo, length…),
  **UTILITY** (octave, transpose, channel, nudge), **ROUTING** (dest, deal, tap, mute-matrix).
Depth comes from *combining* a few of these, not from any single one.

## MIDI IN (the four doors)
Four input **doors A–D**, shown as strips on the machine column — tap one to open its settings. Each door has
a **mode** (how it listens): latch or hold a chord, act as a **scale** or **chord** source, **replay** a
captured loop, or play a loaded **.mid** clip. Per door you can also filter by MIDI channel, set a note range,
and shift octaves.

## MIDI OUT (the four emitters)
Four output **buses A–D**, shown as strips on the machine column. Each emitter stamps its own MIDI channel
(1–16), so one input can drive several synths on different channels; each strip also has a velocity fader, an
octave shift, a SOLO, and a RACK toggle. (The plugin also emits a combined **ALL** copy of everything.)

## The RACK
Open with the **RACK** button (top of the screen). Each emitter gets a small pedalboard of **treatments** —
today the working ones are **OWNS** (this output claims a shared note from the others), **KEY** (duck the
others), and **TURNS** (deal notes across outputs in turn). More treatments are shown as greyed-out "coming"
slots. A per-output switch decides whether that board is in the signal path.

## Automation
Per-machine **AUTO lanes** let a parameter sweep across a part. Separately, **8 macro sliders** are exposed to
your host (DAW) as automatable parameters — you can record/automate those lanes from the host even though
there isn't a dedicated macro panel on screen.

## Scenes
A **16-slot** strip of arrangement snapshots — switch play-grid layouts live (a switch lands on the next pass
while playing). **Hidden by default**: turn it on in the settings (cog) page under Display.

## The reel (RECORD)
Open with the **RECORD** button. It's a tape that captures every pass you play. The pass browser shows recent
passes as tiles (tap to replay) with the selected pass drawn as A–D lanes; **SAVE** exports the selected pass
as a MIDI file.

## Top bar & settings
The top of the screen carries the **RACK** and **RECORD** buttons and the step-rate/tempo control (step rate
is also set per part). The **cog** opens settings — display options (like showing the scene strip) and health
info. MIDI IN/OUT and per-machine settings are reached by tapping the strips on the machine column, not from
top-bar buttons.

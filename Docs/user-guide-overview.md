# 8×8 State — User Guide (section overview)

_A simple, plain-language tour of each part of the app. This is an overview, not a full manual._

## The idea
**Don't sequence notes — sequence what happens to them.** You hold chords in; a grid of *processors*
treats those notes over time (arpeggiate, ratchet, re-voice, gate, and so on); the result plays out.
There are five MIDI outputs: **ALL**, plus four cables **A–D**.

## The rooms
The app has one workspace with three "rooms" you move between, plus a tape (the reel).

- **SELECT** — the browser. An 8×8 of tiles, each a complete *machine* (a chain of processors) shown as a
  little piano-roll fingerprint. Tap a tile to hear it against whatever you're playing; drag the one you like
  onto a play ferry to keep it.
- **PART** — the workbench. The selected ferry's *part* opens here as a step grid (8, or up to 16, columns).
  Each column picks one active row ("rung"); the sweeping playhead steps through them. The machine's chain
  editor (the card) sits below the grid.
- **PLAY** — where parts run together. See "Play ferries" below.

## Play ferries
The row of **8 ferry slots**. Each ferry is a full part.
- **Selector** (top) — opens that ferry's part on the bench (an empty ferry opens the SELECT browser).
- **Play/Stop** (the big button) — starts or stops that ferry. Several can play at once; the active (on-bench)
  ferry plays through the workbench grid, the others play in the background.
- **M (mute)** — silences that ferry's audio; its play light stays on so you can see it's still "running".
- **S (solo)** — when any ferry is soloed, only soloed ferries are heard.
  A muted or solo-excluded ferry (and its part grid) dims so you can see it's silenced.

## The machine (the chain)
A cell is a **machine** — a chain of up to **8 processors** in series, in signal order. Edit the chain in the
card: add/remove stages, pick each stage's type, and bypass any stage to hear its effect. Editing a machine
changes it everywhere it's placed.

## Processors
There are ~32 processor types, grouped by what they do:
- **MELODY** (arp, riff, …), **HARMONY** (harmonize, chords, avoid/lock-to-key, …),
  **RHYTHM** (ratchet, euclid, burst, weave, …), **DYNAMICS** (chance, velocity, humanize, …),
  **CONTROL** (mod — shaped CC/LFO, glide, …), **TIME** (echo, length, …),
  **UTILITY** (octave, transpose, channel, nudge), **ROUTING** (dest, deal, tap, mute-matrix).
Depth comes from *combining* a few of these, not from any single one.

## MIDI IN (receivers)
Four input **doors A–D**. Each door has a **mode** — how it listens: pass notes straight through, latch/hold a
chord, act as a scale or chord source, replay a captured loop, or play a loaded `.mid` clip. Per door you can
also filter by MIDI channel, set a note range, and shift octaves.

## MIDI OUT (emitters)
Four output **buses A–D** (plus ALL). Each emitter stamps its own MIDI channel, so one instrument can drive
several synths on different channels/cables.

## The RACK
Per-emitter **treatments** — a small pedalboard on each output. Toggles arm treatments like *claim* (this
output wins a shared note), *duck*, *turns* (deal notes across outputs), *mono*, *fence* (note-range policy),
*curve* (velocity shaping), and more. A per-output switch decides whether that board is in the signal path.

## Macros
**8 sliders + 8 buttons.** You author a macro to drive many parameters at once, then move the one control (or
automate it from your host — the sliders are exposed as host parameters). This is the main way to automate the
instrument from a DAW.

## Scenes
A **16-slot strip** of arrangement snapshots — switch between different layouts of the play grid live.

## The reel (RECORD)
A tape that captures every pass you play. Open the pass browser to review recorded passes, replay one, or
export it as a MIDI file.

## Header controls
Along the top: **RATE** (step speed + swing), **MIDI IN**, **MIDI OUT**, **RACK**, **ROW 8** (a row of action
buttons), and **RECORD** (the reel).

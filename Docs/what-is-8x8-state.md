# What is 8×8 State?

> **Don't sequence notes. Sequence what happens to them.**

The notes come from your hands — a held chord. What you compose is the sequence of
*transformations* applied to those notes over time and space. "MIDI processor" and "step
sequencer" are both true, but each captures only a slice. Below is the fuller picture: the
several things 8×8 State genuinely is, and the category it invents.

## A MIDI effects rack you can sequence

Every cell on the 8×8 grid is a *processor* — an arp, ratchet, strum, gate, euclid, riff,
chance, harmonize, chord, mod, glide, and more — and cells chain in series like a modular
patch. So it's an arpeggiator generalised well past the breaking point, and a rack, and a
router, all at once. The grid's columns are time; a column decides which treatment your
held chord passes through at that moment.

## A generative engine — but deterministic

Chance, euclid, seeded walks, RANDOMIZE-as-an-ensemble, MUTATE. It generates musical
material rather than storing it. Crucially the generation is *deterministic*: everything is
a pure function of the host beat position and the held chord, so a passage is replay-exact —
it improvises without drifting. Nothing is accumulated across renders; it is all derived.

## A reactive, chord-following instrument

This is the part "sequencer" misses entirely. **Nothing stores pitch.** A RIFF is a stencil
of *ranks*; a CHORDS stage is a stencil of *degrees*; the grid itself is a stencil of
*processes*. Hold any chord, in any key, and the same 8×8 re-derives against it. The
composition is key-agnostic and material-agnostic — it is a *shape*, not a recording. Change
the chord and the whole piece follows.

## A routing and spatial instrument

Five outputs (ALL + emitters A–D), receiver "doors" with modes (thru · latch · hold · keys ·
scale · chord · replay · file), and THE RACK on the emitter side (claim, duck, turns, mono,
fence, curve, conversation). So it also sequences *where* notes go and *whether* they go, not
only what they become — closer to a conditional MIDI matrix than a note sequencer.

## A live performance surface

The rooms / play-ferry interface, live audition, latch doors, and per-part clocks running at
independent tempos make it something you *play* and re-arrange in the moment — not only
program and press play.

## The category it invents: a state machine for live MIDI

The name is literal. Each column is a moment; each cell is a **state** your input passes
through; the grid is the transition table over time. The music isn't inside the plugin and
isn't only in your hands — it lives in the interaction between them.

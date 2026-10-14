# FourStep — Product & Design Reference

*Project Knowledge document for a Claude.ai Project. Upload this file as-is. Companion file:
`fourstep-claude-project-knowledge-visual.md` (palette and visual language).*

## The pitch

Four lanes. One chord. Whatever rhythm you draw.

FourStep is a four-lane Euclidean-rhythm MIDI instrument for iPad: hold a chord, and four
independently-walking rhythmic voices strike it, each shaped by its own hit pattern, its own
walked riff, and its own modifier. It ships two ways — a standalone AUv3 plugin (hosted inside
an app like AUM) and a standalone app that hosts itself.

## Where it comes from

FourStep began life as "Euclideous," one reserved feature inside a much larger MIDI-processing
plugin called MidiSpark, publicly branded "8x8 State" — an 8×8 grid that sequences MIDI
*processors* (arpeggiators, ratchets, chance gates, and twenty-odd others) over time, rather than
sequencing notes directly. Euclideous proved popular and distinct enough on its own terms that
it's now being extracted and released independently, under its own name, as its own product.
8x8 State's wider feature set continues to exist in the same codebase but is not part of
FourStep and is currently on hold as a separate product.

One engine, two shipped products: FourStep and 8x8 State share the same underlying audio-
processing engine (the same render pipeline, the same MIDI-timing guarantees), built as two
separate app + plugin targets rather than a fork or a reskin of one another.

## Why it's genuinely different from "a sequencer"

The thing that distinguishes FourStep from a conventional step sequencer: **nothing in it stores
a pitch.** A riff is a stencil of *ranks* — "the 3rd-lowest note of whatever you're holding," not
"the note E4." Hold a C major triad, the riff plays its shape against C major; hold a D minor
seventh instead, the identical riff immediately plays the equivalent shape against that chord,
with zero re-programming. The composition is a *shape*, not a recording — key-agnostic and
chord-agnostic by construction.

It's also deterministic, not generative-in-the sense of unpredictable: everything a lane does is
a pure function of the current beat position and the chord currently held, so a passage is
replay-exact — it never drifts, even though it can look and sound like a live, reactive
performance.

## The four facets of a lane

FourStep has **four lanes** running independently. Each lane has the same four facets available
— what differs between lanes is which facet is currently doing the talking, and how they're
tuned:

- **Rhythm** — the pattern itself. A Euclidean hit pattern: K pulses distributed as evenly as
  possible across N steps (the classic "Euclidean rhythm" construction — think of the canonical
  3-against-8 tresillo, or 5-against-8 cinquillo). Can be rotated, and tilted so hits bunch early
  or late in the cycle. Has its own direction (forward / backward / ping-pong) and its own
  restart point, independent of the other lanes.
- **Riff** — a walked stencil of ranks. One shared 8-step rank matrix, four independently stored
  riffs (switch which one a lane is walking without losing the others), six walk directions
  (forward, backward, pendulum, ping-pong, random, a biased random walk). Can lock to a fixed
  restart point, invert, tie a note over a rest instead of cutting it. Supports "riff capture" —
  play a line while a chord is held, and FourStep records it as ranks *against that chord*, so it
  replays correctly against any later chord, not just the one you played it against.
- **Notes** — an additive lit-note layer, independent of (and layered on top of) the riff. Up to
  eight ranks can be individually lit, plus two special "top of chord" positions, each with its
  own octave shift. This sounds *alongside* whatever the riff is doing, not instead of it — a
  chord under a moving line is directly buildable.
- **Mask** — a pattern over the pattern. A second K-of-N Euclidean shape gating the lane's own
  hits, with eleven selectable effects when a mask hit lands: mute, pause, ratchet (rapid re-
  strike), repeat the last note, stab the whole chord, shift an octave, mirror/leap/climb the
  rank, accent or swell the velocity. Gated by an adjustable chance, so the mask can be
  probabilistic rather than fixed.

## What's on screen

The page is a full-screen instrument view (not embedded inside the wider 8x8 grid workbench).
Top to bottom:

- **Header** — title, a global reset-span control, a key picker, a built-in chord generator
  (degree matrix + rate — no external routing required), main output toggles for four
  destinations (A–D), on/off, undo/redo.
- **The four lane cards + the shared riff grid** — laid out as six equal boxes (the four lanes,
  the riff grid, and one box held in reserve for a future control), arranged to fit either
  portrait or landscape.
- **The sequencer panel** — a two-tab step grid, separate from the four lanes' own rhythms: a
  LANES tab decides *which of the four lanes sounds* at each step of its own sequence, and a
  RIFFS tab decides *which of the four riffs plays* at each step of its own sequence. This is a
  meta-layer above the four lanes' individual patterns — it's what lets the whole instrument
  evolve over a longer arrangement rather than looping one fixed combination forever.

## Vocabulary — the whole glossary

FourStep deliberately does **not** use the wider 8x8 State vocabulary (there's no receiver/door
routing graph, no multi-cable bus model, no chain of twenty processor types). This is everything:

| Term | Meaning |
|---|---|
| **Lane** | One of four independent voices, each with its own rhythm, riff position, lit notes, and mask. |
| **Riff** | A stencil of ranks over an 8-step grid — four stored, one edited at a time, shared by whichever lanes are currently walking it. |
| **Riff capture** | "Play a line in" — record a played line as ranks against the chord held at that moment. |
| **Mask** | A per-lane modifier pattern (distinct from a similarly-named but unrelated standalone processor that exists elsewhere in the shared engine, outside FourStep's own scope). |
| **Sequencer panel** | The LANES / RIFFS two-tab step grid controlling the meta-level evolution described above. |
| **Main out A–D** | A flat per-lane output toggle — four destinations, nothing more elaborate behind it. |

## v1 scope

**In scope:** the four lanes (rhythm / riff / notes / mask), the shared riff grid and riff
capture, the LANES/RIFFS sequencer panel, choosing a note source (live MIDI in / the built-in
chord generator / a picked key and scale), the four main outputs, undo/redo, a set of twenty
factory presets, and both release forms — the standalone AUv3 and the standalone app hosting it.

**Explicitly out of scope, not an implied roadmap:** the wider 8x8 grid itself, the rooms/play-
ferry performance interface, the full processor chain (arpeggiator, strum, chance, harmonize,
and the twenty-odd other processor types), macro automation, the scene strip, the receiver-door
routing graph, and the wider plugin's own preset system. None of this is assumed to arrive in
FourStep later by default — if any of it is ever wanted, that's a fresh decision to make, not
something already implied by the shared codebase.

## What's genuinely open (don't assume an answer)

- **Target audience and positioning** — not yet defined in anything available to this document;
  treat as an open question rather than inventing a persona or market segment.
- **Pricing, release timing, App Store specifics** — not decided.
- **The exact identity of the standalone release** (its own bundle identity, its own plugin
  component code, separate from the existing MidiSpark/8x8 State identity) — decided in direction
  (FourStep is a genuinely separate target, not a reskin), but the concrete values (what the
  bundle ID actually is, what the plugin's internal component code is) aren't settled and don't
  belong in product/design conversation anyway — that's an engineering decision made in the real
  codebase.

## Status, as of this document

Grounded in the real shipped source as of 2026-10-14. The engine half of the implementation is
fully tested; the on-screen UI has no automated test coverage and is verified by hand on a real
device, so some presentation details may shift between what's described here and what ships —
treat this document as describing the architecture and intent faithfully, not as a pixel-exact
screenshot.

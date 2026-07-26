# RECEIVER STRIP — design spec (from design-side Claude, 2026-07-26)

Preserved verbatim from the channel (`INSTRUCTIONS-receiver-strip.md`). The receivers' functionality +
look-and-feel, settled with the user, ready to build. Also resolves the missing-cable-stepper render flag.

## The strip, PERFORM face (per receiver, R1–R4)
```
 ● R1 ○THRU
 ┌────┬──────┐
 │    │ LATCH│
 │ ▐  │ OCT− │
 │ ▐  │ OCT+ │
 │ ▐  │      │
 └────┴──────┘
  MUTE · SOLO
```
- **Header:** the R-label (identity hue dot) + **the THRU pip** (~12pt dot).
- **Left column: the SLIDER** — the emitter fader's twin: shows MIDI activity (input metering, per-receiver
  attribution) and rides a **momentary-absolute input-velocity override** (touch = absolute, spring on
  release, §5c HOLD latches it). Dark when muted (shipped rule).
- **Right column, the FEATURES:**
  - **LATCH** — the user-definite CHORD-LATCH mode surfaced: tap ON = detect-and-hold the current chord
    hands-free; **a NEW chord REPLACES the held one**; tap OFF = release (this IS the clear — the separate
    CLEAR button was cut: latch-off releases latched notes; physically-held notes rightly persist while
    fingers are down). Lit while holding. The accumulate/pedal variant (SUSTAIN) stays a future CONFIG-level
    mode, never on this face.
  - **OCT− / OCT+** — live register nudge: an **EPHEMERAL octave overlay** (±1 per tap, clamp ±3) composing
    with the config transpose; value displayed beside the buttons when ≠0 ("+1" — deviation announces);
    cleared on transport stop (weather, per the one-model law — the keyboard snaps home).
- **Foot: MUTE · SOLO.**
  - **MUTE** — the front door closes: subscribers derive silence, meter dark, R1-mute gates passthrough (all
    shipped); **the chord-latch SURVIVES silently** (the score switch — unmute and the harmony returns).
    **PERSISTED** — the strip law generalizes: *structure persists (MUTE, CLAIM, THRU); performance
    evaporates (everything else).*
  - **SOLO** — **ephemeral, additive weather**: tap = join the solo set (other receivers' subscribers quiet);
    multi-solo = the union; tap off = leave; stop clears the set. Formula (instrument-wide):
    `audible = ¬muted ∧ (soloSet = ∅ ∨ member)` — a muted receiver stays silent inside the set (console
    convention). Soloed strips GLOW, excluded strips dim. Passthrough ignores solo (stopped-courtesy vs
    playing-tool).

## THE THRU PIP — supersedes the passthrough-follows-R1 LAW
The pip is a **radio across the four strips**: exactly one lit; **tap any strip's pip and THRU moves there
directly** (no cycling). Passthrough (CC/PB/AT + stopped-note soundcheck) follows the pip's receiver — same
mute-gating as today. Default at document birth: R1. PERSISTED (structure).
Trunk: amend the item-11 passthrough sentence — "follows THE THRU PIP's receiver (default R1); the
follows-R1 rule is superseded by visible, movable choice."

## EDIT face (same frame, faces swap per the doctrine)
The feature column swaps for CONFIG: **the CABLE stepper (IN ANY·1–4) returns here** + the CHANNEL stepper;
slider stays (metering never leaves); MUTE·SOLO stay (they're honest in both modes); LATCH/OCT are
PERFORM-face only. This closes render flag (a).

## Cuts + reasons (for the record)
CLEAR — cut (latch-off is the release). MON — rejected (blurs routing; solo covers the need). THRU-as-cycling
— rejected (direct pip tap only).

# Acceptance Criteria — EDIT-TIME DERIVATION SERVICES

_Captured from the ferry `SPEC-edit-time-derivation.md` (design-side Claude, Paul 2026-08-07). SPEC OF RECORD,
NOT yet built. Paul: "the child knows its parent's pitches and lengths — use it."_

One facility: derive the chain-to-slot offline against (live pool → house chord → the reference chord), yielding
the input's full schedule at edit time. Four services ride it, all pure, all cheap.

## ★★ 1. FITTED DEFAULTS — born adjusted to what it eats
A newly-added stage initialises FROM ITS INPUT (newborn-audible extends to newborn-FITTED):
- **GLIDE**: RANGE suggested from the incoming interval span (an octave-spanning arp → offer ±12; the re-anchor
  note shown).
- **ECHO/DELAY**: TIME defaults to a division that INTERLOCKS with the incoming rate (never the same value —
  instant dub, no mud).
- **LENGTH**: SHORT/LONG sliders seeded as fractions of the incoming note lengths.
- **SPLIT**: TOP/BOTTOM n sane vs the pool size. **MASK**: euclid k relative to incoming density. **WEAVE**:
  BASE = the incoming rate. **HARM POOL**: steps within pool span.

Defaults are SUGGESTIONS (pre-set, fully editable) — the stage arrives already musical on YOUR material.

## ★★ 2. THE PICKER PREVIEWS — choose by result, not by name
The processor type picker shows, per candidate, a small WINDOW (canned mode, fed the REAL upstream schedule): you
see what THIS input becomes under each type before committing; tap-to-audition per row. The library gains the same
(a chain previewed against your current material, not the reference).

## 3. DEGENERACY WARNINGS — the dice's audition check, for hands
At edit time, flag before commit: SPLIT TOP 3 on a 2-note source (the wrap notice) · GLIDE RANGE < incoming span
("leaps will re-anchor") · CHNC low on sparse input (density note) · anything the offline derive shows producing
near-silence. Warnings inform, never block.

## 4. ADAPTIVE RANGES + SUMMARIES
Sliders scale useful ranges to the input where sensible (ECHO's repeats×time shown against the 2-pass cap FOR the
actual incoming rate); slot summary lines may state derived facts ("eats 1/16s · slides"). Chrome-quiet: services
whisper, never nag.

## THE FACILITY
`deriveInput(toSlot:, against: pool|house|reference, span: 1 pass)` — the dice's audition machinery, exposed as an
edit-time service. One implementation; the four services + future askers (the EYE's long window) share it.

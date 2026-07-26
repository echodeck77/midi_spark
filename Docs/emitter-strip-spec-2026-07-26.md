# EMITTER STRIP — design spec (from design-side Claude, 2026-07-26)

The receiver strip's twin (see `receiver-strip-spec-2026-07-26.md` — same two-column anatomy, same foot,
same laws). Plus the role family, settled. **Gated behind single-CLAIM device validation** — build UI +
engine when convenient, but the device pass validates CLAIM's ghosts before any of this is trusted.

## The strip, PERFORM face (per emitter, E1–E4)
```
 ● E1  ch1
 ┌────┬───────┐
 │    │ CLAIM │
 │ ▐  │ FLAT  │
 │ ▐  │ ALT   │
 │ ▐  │ OCT−  │
 │ ▐  │ OCT+  │
 └────┴───────┘
  MUTE · SOLO
```
- **RELABEL (user directive): emitters are E1–E4 everywhere.** Cell bus chips abbreviate to the numeral
  (1 2 3 4) — compact, unambiguous by position. [design-side's law; overrule if the chips read worse.]
- **Left column:** the shipped slider (momentary-absolute velocity override + LED ladder). Unchanged.
- **THE ROLE BUTTONS — one grammar: TAP = toggle · VERTICAL DRAG = the role's one parameter** (value shown
  beside the button when ≠ default; deviation announces):
  - **CLAIM** (multi-select, SHARED tier semantics: claimants' union suppresses non-claimants by pitch-class;
    claimants never suppress each other). **Drag = LEAK %** (0 = classic hard claim; >0 = suppressed notes
    pass at scaled velocity — the hole becomes a shadow). Persisted (structure).
  - **FLATTEN** — activity ducking: while this emitter has anything sounding, OTHER emitters' NEW note-ons
    arrive velocity-scaled; silence = instant bloom back. Sounding notes never lurch (the shipped velocity
    rule). **Drag = amount %.** Persisted.
  - **ALT** — turn-taking: **all ALT-lit emitters form ONE group, turns in position order** (2 lit =
    ping-pong; 3–4 lit = round-robin — the parked HOCKET dissolves into this, delete its parked entry).
    **Drag = COUNT** (notes per turn, 1·2·3·4; default 1). Persisted.
  - **FLIP — CUT (user catch, logged):** FLIP(x) ≡ CLAIM(all others) under SHARED semantics; the sole
    inexpressible case (mutual multi-flip avoidance) is tick-order-dependent and musically dubious. Never build.
  - **OCT− / OCT+** — ephemeral output-register overlay: ±12 stamped on outgoing notes, clamp ±3, value shown
    when ≠0, cleared on stop (weather; the receiver OCT's mirror).
- **Foot: MUTE · SOLO** — exactly the receiver behaviours: MUTE persisted (the emission gate as shipped),
  SOLO ephemeral additive (`audible = ¬muted ∧ (set empty ∨ member)`), glow/dim, stop clears.
- **Strip law (both bands): structure persists — MUTE · CLAIM · FLATTEN · ALT · THRU; performance evaporates
  — sliders, solos, OCT.**

## EDIT face
Role column swaps for config: the CHANNEL stepper (as shipped) + reserved space for the future WIRE-INSERT
chip (item 14 — do not build, just don't crowd the slot). Slider + MUTE·SOLO stay.

## Engine + gating notes
- FLATTEN = "is it sounding" refcount query + admission-time velocity scale (stateless). ALT = a per-group
  turn counter at emission (derived from note-index within the group; position order breaks ties, same as
  CLAIM's L1).
- The whole family remains gated behind single-CLAIM device validation.

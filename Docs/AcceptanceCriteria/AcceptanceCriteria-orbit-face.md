# AcceptanceCriteria — THE ORBIT (the derived cell face)
_From the design side (REPLY-select-answer-orbit-spec §3, 2026-08-02). The ORBIT is a figure DERIVED
from a cell's behavioural config — a lissajous-style path drawn on the cell. It REPLACES the type
emblem + digest text on occupied cell faces (single-type faces stopped being true once chains
shipped). "The orbit cannot be dressed — that is its entire authority." Pure derivation, document-
visible truth: same config ⇒ same figure on every device._

## A — THE GENERATING HASH
**A1. Behavioural config hash.** The orbit derives from the SAME equality that defines TWINS:
- INCLUDED: chain (slots + params + per-slot bypass) · input source (receiver) · output (emitters +
  ALT set + the three CHOP masks) · triggers (when they re-host).
- EXCLUDED: colour, name, MUTE (chrome — a muted twin still twins), grid position.
**A2. Stable 32-bit hash.** Serialize the included config stably → 32-bit FNV/murmur. Document the
byte order (the drawing is document-visible truth). Twins share one hash ⇒ share one figure.

## B — HASH → FIGURE (three draws)
**B1. RATIO** from the table `[1:2, 2:3, 3:4, 3:5, 4:5, 5:6, 2:5, 3:7]` → `(a, b)` = the sin
multipliers for x and y.
**B2. PHASE** `φ ∈ [0, 2π)` = `hash mod 628 / 100`.
**B3. SQUISH** `∈ [0.62, 0.94]` = vertical ellipse factor.
**B4. Path.** `p(t) = (cx + rx·sin(a·t + φ), cy + ry·squish·sin(b·t))`, `t ∈ [0, 2π]`,
~140 segments at cell size / 200 at edit size. CACHE one path per unique hash — twins share the
cached path (×64 grid stays cheap by construction).

## C — THE FACE GRAMMAR (cell-machine era)
**C1.** Occupied cell face = **hue block (whose) · THE ORBIT (which) · bus dots (where)**.
**C2.** The type emblem AND the digest text RETIRE from the cell face.
**C3. Ink:** `rgba(12,12,16,0.42)`, 1.6pt stroke, round caps — above the bus dots' weight, below
nothing (the orbit IS the face).

## D — MOTION = MIDI ONLY (invisible=frozen holds)
**D1. Silent cell:** the path renders STATIC at rest ink. No timers.
**D2. Note event** (tie to the existing per-cell emission/diagnostics feed): a COMET enters the path
— its head advances along `t` at ~0.9 cycles/sec while events continue; TRAIL length ∝ velocity
(~18·vel segments behind the head); the path ink BRIGHTENS by up to +0.35α on strike, decaying
~450 ms. Rapid notes = the comet keeps running + re-glows (ONE traveller per cell — never spawn
multiple; budget law).
**D3. Death:** the comet dies (path back to rest ink, frozen) ~1 s after the last event.

## E — THE EDIT PAGE
**E1.** IDENTITY hosts the orbit LARGE (beside the 4×4 hue picker).
**E2. Glide on change:** on ANY config change, recompute the hash, then GLIDE — interpolate
`(a, b, φ, squish)` linearly over ~400 ms (a re-tune, never a snap).
**E3.** While the audition loop runs, the big orbit carries the comet too (same D rules) — shaping
the machine is watching its signature learn the new figure.

## F — TWINS + LIBRARY
**F1.** Twin-advertise (the whole-cell cyan pulse) is unchanged and now doubly legible: pulsing cells
VISIBLY share one figure. Border (selection dash) · fill (pulse) · ink (orbit) never conflict — three
layers.
**F2. Library:** NO orbit in the library (machine-minus-routing has no full hash) — the library keeps
its text row; the orbit appears the moment a library chain lands in a real cell.

## G — TUNING (pre-agreed)
If it under-reads on device: segment count, ink alpha, stroke weight, comet size may be tuned.
NEVER tune: colour tint, autonomous motion, user editing.
